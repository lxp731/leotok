"""
Core download logic — refactored from the `pd` bash script.

Calls yt-dlp CLI via subprocess to guarantee identical behaviour.
"""

from __future__ import annotations

import os
import re
import signal
import subprocess
import tempfile
from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable


@dataclass
class DownloadTask:
    """Tracks the state of a single download."""

    task_id: str
    url: str
    start_time: str
    duration: int
    quality: str = "720p"
    proxy: str | None = "http://127.0.0.1:7890"

    # Runtime state
    status: str = "pending"  # pending | downloading | done | failed | cancelled
    progress: float = 0.0  # 0–100
    speed: str | None = None
    eta: str | None = None
    filename: str | None = None
    filepath: str | None = None
    filesize: str | None = None
    error: str | None = None
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())

    # Internal handle for cancellation
    _cancelled: bool = field(default=False, repr=False)
    _process: subprocess.Popen | None = field(default=None, repr=False)


# ---- Time parsing (from pd bash script) ----

def parse_time_to_seconds(time_str: str) -> int:
    """Parse MM:SS or HH:MM:SS to total seconds.

    >>> parse_time_to_seconds("01:30")
    90
    >>> parse_time_to_seconds("1:07:25")
    4045
    """
    parts = time_str.strip().split(":")
    if len(parts) == 2:
        minutes, seconds = int(parts[0]), int(parts[1])
        return minutes * 60 + seconds
    elif len(parts) == 3:
        hours, minutes, seconds = int(parts[0]), int(parts[1]), int(parts[2])
        return hours * 3600 + minutes * 60 + seconds
    else:
        raise ValueError(f"Unsupported time format: {time_str!r}, use MM:SS or HH:MM:SS")


def _seconds_to_hms(total_sec: int) -> str:
    """Convert total seconds to HH:MM:SS format (for yt-dlp --download-sections)."""
    h = total_sec // 3600
    m = (total_sec % 3600) // 60
    s = total_sec % 60
    return f"{h:02d}:{m:02d}:{s:02d}"


# ---- Format string builder ----

def _build_format_string(quality: str = "720p") -> str:
    """Build the yt-dlp format selection string.

    Mirrors the pd script logic:
      Prefer m3u8 720p MP4; fall back to any 720p MP4; last resort any 720p.
    """
    height = quality.rstrip("p")
    return (
        # Prefer non-HLS MP4 — gives standard [download] XX.X% progress lines.
        # Fall back to m3u8 HLS (ffmpeg progress, harder to parse), then combined.
        f"bv[height={height}][ext=mp4]+ba[ext=m4a]"
        f"/bv[height={height}][ext=mp4][protocol=m3u8]"
        f"+ba[ext=m4a][protocol=m3u8]"
        f"/b[height={height}][ext=mp4]"
    )


# ---- Progress parsing ----
# yt-dlp progress line examples:
#   [download]  12.3% of ~100.00MiB at  5.20MiB/s ETA 00:17
#   [download]  12.3% of  100.00MiB at    5.20MiB/s ETA 00:17 (frag 1/10)
#   [download] 100.0% of ~1.00MiB           (short download, no speed/ETA)
#
# Strategy: percentage is mandatory. Speed / ETA / frag are optional so
# the regex never misses a progress update just because auxiliary fields
# are omitted.

# Fallback — matches any "[download]  XX.X%" pattern regardless of extras.
_PCT_FALLBACK_RE = re.compile(r"\[download\]\s+([\d.]+)%")

# Rich regex — also captures speed, ETA and optional fragment info.
# Groups: 1=pct  2=filesize  3=speed  4=eta  5=frag_cur  6=frag_total
_FULL_PROGRESS_RE = re.compile(
    r"\[download\]\s+([\d.]+)%\s+of\s+~?\s*(\S+)?"
    r"(?:\s+at\s+(\S+)\s+ETA\s+(\S+))?"
    r"(?:\s+\(frag\s+(\d+)/(\d+)\))?"
)

# ffmpeg structured progress (via -progress pipe:2 -nostats):
#   out_time=00:00:04.260000
# Groups: 1=hours  2=minutes  3=seconds
_FFMPEG_TIME_RE = re.compile(r"^out_time=(\d+):(\d+):([\d.]+)")


def _parse_progress(
    line: str, task: DownloadTask, total_duration: int = 0
) -> None:
    """Extract progress / speed / ETA from a yt-dlp / ffmpeg stderr line."""
    if task._cancelled:
        return

    # ── yt-dlp native progress: "[download]  XX.X%" ──
    m = _PCT_FALLBACK_RE.search(line)
    if m:
        try:
            task.progress = float(m.group(1))
        except ValueError:
            pass
        # Try full regex for speed / ETA on the same line
        fm = _FULL_PROGRESS_RE.search(line)
        if fm:
            if fm.group(3) is not None:
                task.speed = fm.group(3)
            if fm.group(4) is not None:
                task.eta = fm.group(4)
        return

    # ── ffmpeg progress: "frame=... time=HH:MM:SS.xx" ──
    m = _FFMPEG_TIME_RE.search(line)
    if m and total_duration > 0:
        try:
            h, mi, s = int(m.group(1)), int(m.group(2)), float(m.group(3))
            elapsed = h * 3600 + mi * 60 + s
            task.progress = min(100.0, elapsed / total_duration * 100.0)
        except (ValueError, ZeroDivisionError):
            pass
        return


# ---- Main download function ----

def download_segment(task: DownloadTask, output_dir: str, on_update: Callable) -> None:
    """Download a video segment by calling the yt-dlp CLI (subprocess).

    This mirrors the `pd` bash script exactly, avoiding Python API quirks
    around --download-sections.
    """
    start_sec = parse_time_to_seconds(task.start_time)
    end_sec = start_sec + task.duration
    start_hms = _seconds_to_hms(start_sec)
    end_hms = _seconds_to_hms(end_sec)
    section = f"*{start_hms}-{end_hms}"

    print(f"🔍 Download segment: start_time={task.start_time!r}, duration={task.duration}")
    print(f"   start_sec={start_sec}, end_sec={end_sec}, section={section}")

    start_str = f"{start_sec // 60:02d}{start_sec % 60:02d}"
    end_str = f"{end_sec // 60:02d}{end_sec % 60:02d}"
    output_template = os.path.join(output_dir, f"%(title)s_{start_str}-{end_str}.%(ext)s")

    # Use a temp file so yt-dlp writes the final file path after any
    # post-processing (e.g. ffmpeg trimming for --download-sections).
    _filename_info = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    _filename_info.close()
    _filename_tmp = _filename_info.name

    output_file: str | None = None

    cmd = [
        "yt-dlp",
        "-f", _build_format_string(task.quality),
        "--download-sections", section,
        "--no-playlist",
        "--user-agent",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36",
        "--impersonate", "chrome",
        "--socket-timeout", "30",
        "--retries", "3",
        "--no-part",
        "--downloader-args", "ffmpeg:-progress pipe:2 -nostats",
        "-o", output_template,
        "--print-to-file", "after_move:filepath", _filename_tmp,
        task.url,
    ]

    if task.proxy:
        cmd.insert(1, "--proxy")
        cmd.insert(2, task.proxy)

    print(f"   cmd: {' '.join(cmd)}")

    def _read_filename_from_temp() -> None:
        """Read the actual output file path that yt-dlp saved via --print-to-file."""
        nonlocal output_file
        try:
            with open(_filename_tmp) as f:
                path = f.read().strip()
                if path:
                    output_file = path
        except OSError:
            pass

    def _cleanup_temp() -> None:
        """Remove the temp file used for --print-to-file."""
        try:
            os.unlink(_filename_tmp)
        except OSError:
            pass

    try:
        task.status = "downloading"
        on_update(task)

        # --downloader-args "ffmpeg:-progress pipe:2 -nostats" tells ffmpeg
        # to write structured progress (one field per line, \n-delimited)
        # instead of its default \r-overwrites.  Structured output flushes
        # per-line even through yt-dlp's internal pipe, giving real-time
        # updates.
        task._process = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=os.setsid,
        )

        for line in task._process.stderr:  # type: ignore[union-attr]
            if task._cancelled:
                os.killpg(os.getpgid(task._process.pid), signal.SIGTERM)
                task._process.wait()
                break
            line = line.strip()
            if line:
                _parse_progress(line, task, task.duration)
                on_update(task)

        if task._cancelled:
            task.status = "cancelled"
            _read_filename_from_temp()
            if output_file is not None:
                _cleanup_file(output_file)
            _cleanup_temp()
            on_update(task)
            return

        exit_code = task._process.wait()

        # Read the actual file path that yt-dlp wrote via --print-to-file
        _read_filename_from_temp()

        if exit_code == 0 and output_file is not None and os.path.isfile(output_file) and os.path.getsize(output_file) > 0:
            size_bytes = os.path.getsize(output_file)
            task.filename = os.path.basename(output_file)
            task.filepath = output_file
            task.filesize = _format_size(size_bytes)
            task.progress = 100.0
            task.status = "done"
            on_update(task)
        else:
            task.status = "failed"
            task.error = f"yt-dlp exited with code {exit_code}"
            if output_file is not None:
                _cleanup_file(output_file)
            on_update(task)

    except FileNotFoundError:
        task.status = "failed"
        task.error = "yt-dlp not found. Install with: uv add yt-dlp"
        on_update(task)

    except Exception as e:
        import traceback
        traceback.print_exc()
        task.status = "failed"
        task.error = str(e)
        _read_filename_from_temp()
        if output_file is not None:
            _cleanup_file(output_file)
        on_update(task)
    finally:
        _cleanup_temp()


def _cleanup_file(path: str) -> None:
    """Remove incomplete output file (mirrors cleanup_partial trap in pd script)."""
    try:
        if os.path.isfile(path):
            os.remove(path)
    except OSError:
        pass


def _format_size(num_bytes: float) -> str:
    """Format bytes to human-readable string."""
    for unit in ("B", "KB", "MB", "GB"):
        if num_bytes < 1024:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024
    return f"{num_bytes:.1f} TB"
