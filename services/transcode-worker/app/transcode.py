LADDER = [
    {"name": "360p", "height": 360, "vbitrate": "800k", "abitrate": "96k"},
    {"name": "720p", "height": 720, "vbitrate": "2800k", "abitrate": "128k"},
    {"name": "1080p", "height": 1080, "vbitrate": "5000k", "abitrate": "192k"},
]


def build_hls_cmd(src: str, out_dir: str) -> list[str]:
    """One ffmpeg pass -> 3 HLS variants + a master playlist under out_dir/<n>/."""
    n = len(LADDER)
    # filter_complex: split input into n, scale each to its height
    split = f"[0:v]split={n}" + "".join(f"[v{i}]" for i in range(n)) + ";"
    scales = ";".join(
        f"[v{i}]scale=w=-2:h={r['height']}[v{i}out]" for i, r in enumerate(LADDER)
    )
    cmd = ["ffmpeg", "-y", "-i", src, "-filter_complex", split + scales]
    # per-rung video encode
    for i, r in enumerate(LADDER):
        cmd += ["-map", f"[v{i}out]", f"-c:v:{i}", "libx264", f"-b:v:{i}", r["vbitrate"]]
    # per-rung audio (duplicated from the single source audio stream a:0)
    for i, r in enumerate(LADDER):
        cmd += ["-map", "a:0", f"-c:a:{i}", "aac", f"-b:a:{i}", r["abitrate"]]
    var_map = " ".join(f"v:{i},a:{i}" for i in range(n))
    cmd += [
        "-f", "hls",
        "-hls_time", "6",
        "-hls_playlist_type", "vod",
        "-master_pl_name", "master.m3u8",
        "-var_stream_map", var_map,
        "-hls_segment_filename", f"{out_dir}/%v/seg_%03d.ts",
        f"{out_dir}/%v/index.m3u8",
    ]
    return cmd


def build_thumbnail_cmd(src: str, out_path: str) -> list[str]:
    # seek to 1s, grab exactly 1 frame
    return ["ffmpeg", "-y", "-i", src, "-ss", "00:00:01", "-vframes", "1", out_path]
