import { useState } from "react";
import { login } from "./auth";
import { makeApi } from "./api";

export default function App() {
  const [token, setToken] = useState(null);
  const [items, setItems] = useState([]);
  const [playUrl, setPlayUrl] = useState(null);
  const api = token ? makeApi(token) : null;

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
  async function watch(id) { setPlayUrl((await api.playback(id)).playbackUrl); }

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
      {playUrl && <video src={playUrl} controls width="480" />}
    </div>
  );
}
