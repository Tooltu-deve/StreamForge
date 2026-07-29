import { useState, useRef, useEffect } from "react";
import Hls from "hls.js";
import { login } from "./auth";
import { makeApi } from "./api";

export default function App() {
  const [token, setToken] = useState(null);
  const [items, setItems] = useState([]);
  const [playUrl, setPlayUrl] = useState(null);
  const api = token ? makeApi(token) : null;
  const videoRef = useRef(null);


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
    if (v.canPlayType("application/vnd.apple.mpegurl")) {   // Safari: HLS native
      v.src = playUrl;
    } else if (Hls.isSupported()) {                          // Chrome/FF: hls.js
      const hls = new Hls();
      hls.loadSource(playUrl);
      hls.attachMedia(v);
      return () => hls.destroy();                            // dọn khi đổi video
    }
  }, [playUrl]);


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
      <ul>{items.map((v) => <li key={v.videoId}><button onClick={() => watch(v.videoId)}>{v.filename}</button></li>)}</ul>
      {playUrl && <video ref={videoRef} controls width="480" />}
    </div>
  );
}
