import { useState, useRef, useEffect } from "react";
import Hls from "hls.js";
import { login } from "./auth";
import { makeApi } from "./api";

export default function App() {
  const [token, setToken] = useState(null);
  const [items, setItems] = useState([]);
  const [playUrl, setPlayUrl] = useState(null);
  const [levels, setLevels] = useState([]);
  const api = token ? makeApi(token) : null;
  const videoRef = useRef(null);
  const hlsRef = useRef(null);


  async function doLogin(e) {
    e.preventDefault();
    const f = e.target;
    setToken(await login(f.email.value, f.password.value));
  }
  async function refresh() { setItems((await api.list()).items || []); }
  async function doUpload(e) {
    e.preventDefault();
    const file = e.target.file.files[0];
    const { uploadUrl } = await api.createUpload(file.name);
    await fetch(uploadUrl, { method: "PUT", body: file });   // PUT thẳng lên S3 (presigned)
    await refresh();
  }

  async function watch(id) {
    const r = await api.playback(id);
    if (!r.playbackUrl) { alert("Đang xử lý, thử lại sau"); return; }  // 409
    setPlayUrl(r.playbackUrl);
  }

  useEffect(() => {
    const v = videoRef.current;
    if (!v || !playUrl) return;
    setLevels([]);                                          // reset khi đổi video
    // Ưu tiên hls.js khi hỗ trợ MSE (desktop, kể cả Chrome tự nhận HLS native) -> có menu
    // chọn rung + điều khiển ABR. Native chỉ dành cho nơi không có MSE (iOS Safari).
    if (Hls.isSupported()) {
      const hls = new Hls();
      hlsRef.current = hls;
      hls.loadSource(playUrl);
      hls.attachMedia(v);
      hls.on(Hls.Events.MANIFEST_PARSED, () => setLevels(hls.levels)); // lấy các rung
      return () => { hls.destroy(); hlsRef.current = null; };          // dọn khi đổi video
    } else if (v.canPlayType("application/vnd.apple.mpegurl")) {        // iOS Safari: HLS native
      v.src = playUrl;
    }
  }, [playUrl]);

  function setQuality(e) {
    // -1 = Auto (ABR); i = ép cố định rung i
    if (hlsRef.current) hlsRef.current.currentLevel = Number(e.target.value);
  }


  if (!token)
    return (
      <form onSubmit={doLogin}>
        <input name="email" placeholder="email" />
        <input name="password" type="password" placeholder="password" />
        <button>Login</button>
      </form>
    );

  return (
    <div>
      <button onClick={refresh}>Refresh</button>
      <form onSubmit={doUpload}>
        <input name="file" type="file" />
        <button>Upload</button>
      </form>
      <ul>{items.map((v) => <li key={v.videoID}><button onClick={() => watch(v.videoID)}>{v.filename}</button></li>)}</ul>
      {playUrl && (
        <div>
          {levels.length > 0 && (
            <select defaultValue="-1" onChange={setQuality}>
              <option value="-1">Auto</option>
              {levels.map((l, i) => <option key={i} value={i}>{l.height}p</option>)}
            </select>
          )}
          <div><video ref={videoRef} controls width="480" /></div>
        </div>
      )}
    </div>
  );
}
