"""
FastAPI server for the Video Downloader app.

Runs inside Termux on Android. The Flutter app communicates with this
server via localhost HTTP.

Start with:
    python server.py
    # or: uvicorn server:app --host 127.0.0.1 --port 8000
"""

from __future__ import annotations

import asyncio
import json
import os
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import aiohttp
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from downloader import DownloadTask, download_segment

# ---- Config ----
OUTPUT_DIR = os.environ.get("VD_OUTPUT_DIR", "/sdcard/Download")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Completed/failed/cancelled tasks are persisted here so the download
# history survives a server restart (the task dict itself is in-memory).
_STATE_FILE = os.path.join(os.path.expanduser("~"), ".leotok_tasks_state.json")
_MAX_PERSISTED_TASKS = 200

app = FastAPI(title="Video Downloader Backend", version="0.1.0")

# Allow Flutter app on localhost to call us
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---- In-memory task store ----
tasks: dict[str, DownloadTask] = {}
_executor = ThreadPoolExecutor(max_workers=2)
_task_lock = asyncio.Lock()


# ---- Helper ----
def _task_to_dict(t: DownloadTask) -> dict[str, Any]:
    return {
        "task_id": t.task_id,
        "url": t.url,
        "start_time": t.start_time,
        "duration": t.duration,
        "quality": t.quality,
        "status": t.status,
        "progress": t.progress,
        "speed": t.speed,
        "eta": t.eta,
        "filename": t.filename,
        "filepath": t.filepath,
        "filesize": t.filesize,
        "error": t.error,
        "created_at": t.created_at,
    }


def _update_callback(task: DownloadTask) -> None:
    """Called from downloader thread — just updates the in-memory task.
    The async poll endpoint reads this state. Terminal states are also
    persisted so history survives a server restart."""
    if task.status in ("done", "failed", "cancelled"):
        _save_state()


# ---- Persistence ----


def _save_state() -> None:
    """Persist the most recent tasks (terminal states survive restarts)."""
    try:
        recent = sorted(tasks.values(), key=lambda t: t.created_at, reverse=True)[
            :_MAX_PERSISTED_TASKS
        ]
        with open(_STATE_FILE, "w") as f:
            json.dump([_task_to_dict(t) for t in recent], f)
    except OSError:
        pass


def _load_state() -> None:
    """Restore persisted tasks on startup. Done tasks whose file is missing
    from disk are dropped (the user deleted them outside the app)."""
    try:
        with open(_STATE_FILE) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return
    if not isinstance(data, list):
        return
    for d in data:
        if not isinstance(d, dict):
            continue
        # Fields are coerced with str()/int()/float() so a corrupt record
        # can't crash the server during restore.
        t = DownloadTask(
            task_id=str(d.get("task_id", "")),
            url=str(d.get("url", "")),
            start_time=str(d.get("start_time", "00:00")),
            duration=int(d.get("duration", 0)),
            quality=str(d.get("quality", "720p")),
            proxy=d.get("proxy"),
            status=str(d.get("status", "failed")),
            progress=float(d.get("progress", 0.0)),
            speed=d.get("speed"),
            eta=d.get("eta"),
            filename=d.get("filename"),
            filepath=d.get("filepath"),
            filesize=d.get("filesize"),
            error=d.get("error"),
            created_at=str(d.get("created_at", "")),
        )
        if not t.task_id:
            continue
        # Never restore in-flight tasks — yt-dlp state is gone.
        if t.status in ("pending", "downloading"):
            t.status = "failed"
            t.error = "服务器重启，任务已中断"
        # Done tasks whose file disappeared are dropped.
        if t.status == "done":
            path = t.filepath or (
                os.path.join(OUTPUT_DIR, t.filename) if t.filename else None
            )
            if not path or not os.path.isfile(path):
                continue
        tasks[t.task_id] = t
    # Persist the cleaned-up state so dropped tasks don't resurrect.
    _save_state()


# ---- Request Models ----


class DownloadRequest(BaseModel):
    url: str
    start_time: str = Field(..., description="Start time, e.g. '01:30' or '1:07:25'")
    duration: int = Field(
        ..., ge=0, description="Duration in seconds. 0 = download full video."
    )
    quality: str | None = Field(default="720p", description="e.g. 480p, 720p, 1080p")
    proxy: str | None = Field(default=None, description="e.g. http://127.0.0.1:7890")
    output_dir: str | None = Field(
        default=None, description="Override output directory"
    )


class ProxyTestRequest(BaseModel):
    proxy: str


# ---- API Endpoints ----


@app.get("/api/health")
async def health():
    """Health check — Flutter app calls this on startup to verify Termux server is alive."""
    import yt_dlp

    return {
        "status": "ok",
        "yt_dlp_version": yt_dlp.version.__version__,  # pyright: ignore[reportAttributeAccessIssue]
        "output_dir": OUTPUT_DIR,
    }


@app.post("/api/download")
async def start_download(req: DownloadRequest):
    """Start a new download task. Returns immediately with task_id."""
    task = DownloadTask(
        task_id=str(uuid.uuid4())[:8],
        url=req.url,
        start_time=req.start_time,
        duration=req.duration,
        quality=req.quality or "720p",
        proxy=req.proxy,
    )
    tasks[task.task_id] = task
    task.status = "downloading"

    # Run yt-dlp in a thread so it doesn't block the async event loop
    _executor.submit(
        download_segment,
        task,
        req.output_dir or OUTPUT_DIR,
        _update_callback,
    )

    return _task_to_dict(task)


@app.get("/api/tasks")
async def list_tasks():
    """List all tasks (most recent first)."""
    return [
        _task_to_dict(t)
        for t in sorted(tasks.values(), key=lambda t: t.created_at, reverse=True)
    ]


@app.get("/api/tasks/{task_id}")
async def get_task(task_id: str):
    """Get a single task's status (polled by Flutter during download)."""
    task = tasks.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return _task_to_dict(task)


@app.delete("/api/tasks/{task_id}")
async def cancel_task(task_id: str):
    """Cancel a running task and delete its partial file."""
    task = tasks.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    task._cancelled = True
    return {"status": "cancelled"}


@app.delete("/api/videos/{task_id}")
async def delete_video(task_id: str):
    """Delete a completed download (file + task record)."""
    task = tasks.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    if task.filename:
        # Prefer the recorded filepath (respects custom download dirs);
        # fall back to the default output dir for legacy records.
        filepath = task.filepath or os.path.join(OUTPUT_DIR, task.filename)
        try:
            os.remove(filepath)
        except OSError:
            pass
    del tasks[task_id]
    _save_state()
    return {"status": "deleted"}


@app.get("/api/videos/{task_id}/file")
async def get_video_file(task_id: str):
    """Stream a downloaded video file for in-app playback."""
    task = tasks.get(task_id)
    if not task or not task.filename:
        raise HTTPException(status_code=404, detail="File not found")
    filepath = os.path.join(OUTPUT_DIR, task.filename)
    if not os.path.isfile(filepath):
        raise HTTPException(status_code=404, detail="File missing on disk")
    return FileResponse(filepath, media_type="video/mp4")


@app.post("/api/proxy/test")
async def test_proxy(req: ProxyTestRequest):
    """Test if a proxy is reachable by trying to fetch a known URL."""
    url = req.proxy
    if not url:
        return {"ok": False, "message": "No proxy configured"}
    try:
        async with (
            aiohttp.ClientSession() as session,
            session.get(
                "https://www.google.com",
                proxy=url,
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp,
        ):
            return {"ok": True, "message": f"Proxy OK (status {resp.status})"}
    except Exception as e:  # noqa: BLE001 - any proxy error becomes a
        # user-friendly "not ok" response instead of a 500.
        return {"ok": False, "message": str(e)}


# ---- Main ----

if __name__ == "__main__":
    import uvicorn

    _load_state()

    print("🎬 Video Downloader Backend starting...")
    print(f"📂 Output dir: {OUTPUT_DIR}")
    print(f"💾 Restored {len(tasks)} task(s) from state file")
    print("🌐 Listening on http://127.0.0.1:8000")
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")
