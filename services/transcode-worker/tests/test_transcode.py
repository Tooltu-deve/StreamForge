from app.transcode import LADDER, build_hls_cmd, build_thumbnail_cmd


def test_ladder_is_three_rungs():
    assert [r["height"] for r in LADDER] == [360, 720, 1080]


def test_build_hls_cmd_has_master_and_three_variants():
    cmd = build_hls_cmd("/tmp/in.mp4", "/tmp/out")
    assert cmd[0] == "ffmpeg"
    assert "/tmp/in.mp4" in cmd
    joined = " ".join(cmd)
    assert joined.count("-b:v:") == 3          # 3 rung -> 3 bitrate video
    assert "master.m3u8" in joined             # có master playlist
    assert "v:0,a:0 v:1,a:1 v:2,a:2" in joined # map 3 variant stream


def test_build_thumbnail_cmd_single_frame():
    cmd = build_thumbnail_cmd("/tmp/in.mp4", "/tmp/t.jpg")
    assert cmd[0] == "ffmpeg"
    assert "-vframes" in cmd and "1" in cmd    # trích đúng 1 frame
    assert cmd[-1] == "/tmp/t.jpg"
