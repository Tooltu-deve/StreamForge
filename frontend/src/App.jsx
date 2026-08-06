import { useState, useRef, useEffect } from "react";
import Hls from "hls.js";
import { login } from "./auth";
import { makeApi } from "./api";
import "./App.css";

function formatDate(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  return isNaN(d)
    ? ""
    : d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function Login({ onLogin }) {
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    const f = e.target;
    setBusy(true);
    setError(null);
    try {
      onLogin(await login(f.email.value, f.password.value), f.email.value);
    } catch (err) {
      setError(err.message || "Sign-in failed. Check your email and password.");
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <h1 className="login-headline">StreamForge.</h1>
      <p className="login-tagline">Upload once. Stream anywhere.</p>
      <form className="login-form" onSubmit={submit}>
        <input className="input-pill" name="email" type="email" placeholder="Email" autoComplete="email" required />
        <input className="input-pill" name="password" type="password" placeholder="Password" autoComplete="current-password" required />
        <button className="btn-pill btn-pill-lg" disabled={busy}>
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
      {error && <p className="login-error">{error}</p>}
      <p className="login-fineprint">Videos transcode to HLS and stream through CloudFront.</p>
    </div>
  );
}

function Player({ video, playUrl, onClose, onRefresh }) {
  const videoRef = useRef(null);
  const hlsRef = useRef(null);
  const [levels, setLevels] = useState([]);
  const [quality, setQuality] = useState(-1); // -1 = Auto (ABR)

  useEffect(() => {
    const v = videoRef.current;
    if (!v || !playUrl) return;
    setLevels([]);
    setQuality(-1);
    // Ưu tiên hls.js khi hỗ trợ MSE (desktop) -> có menu chọn chất lượng + ABR.
    // Native chỉ dành cho nơi không có MSE (iOS Safari).
    if (Hls.isSupported()) {
      // withCredentials: gửi kèm CloudFront signed cookie ở mỗi request segment (cùng origin).
      const hls = new Hls({ xhrSetup: (xhr) => { xhr.withCredentials = true; } });
      hlsRef.current = hls;
      hls.loadSource(playUrl);
      hls.attachMedia(v);
      hls.on(Hls.Events.MANIFEST_PARSED, () => setLevels(hls.levels));
      // Cookie hết hạn -> CloudFront 403 -> xin cookie mới rồi tải tiếp (luồng short-lived).
      hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal && data.type === Hls.ErrorTypes.NETWORK_ERROR && data.response?.code === 403) {
          onRefresh().then(() => hls.startLoad()).catch(() => {});
        }
      });
      return () => { hls.destroy(); hlsRef.current = null; };
    } else if (v.canPlayType("application/vnd.apple.mpegurl")) {
      v.src = playUrl;
    }
  }, [playUrl]);

  function pickQuality(i) {
    if (hlsRef.current) hlsRef.current.currentLevel = i;
    setQuality(i);
  }

  return (
    <section className="player-tile">
      <div className="player-inner">
        <div className="player-head">
          <h2 className="player-title">{video.filename}</h2>
          <button className="btn-icon-circle" onClick={onClose} aria-label="Close player">✕</button>
        </div>
        <div className="player-frame">
          <video ref={videoRef} controls autoPlay />
        </div>
        {levels.length > 0 && (
          <div className="quality-row" role="group" aria-label="Playback quality">
            <button className={`chip${quality === -1 ? " selected" : ""}`} onClick={() => pickQuality(-1)}>
              Auto
            </button>
            {levels.map((l, i) => (
              <button key={i} className={`chip${quality === i ? " selected" : ""}`} onClick={() => pickQuality(i)}>
                {l.height}p
              </button>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function VideoCard({ video, onPlay }) {
  const ready = video.status === "ready";
  return (
    <div className="card">
      <div className="thumb">
        {ready && video.thumbnail_key ? (
          <img src={`/${video.thumbnail_key}`} alt="" loading="lazy" />
        ) : (
          <span className="thumb-glyph">▶</span>
        )}
      </div>
      <p className="card-name" title={video.filename}>{video.filename}</p>
      <p className="card-date">{formatDate(video.uploaded_at)}</p>
      {ready ? (
        <button className="text-link card-action" onClick={onPlay}>Play</button>
      ) : (
        <p className="card-status">Processing — refresh to check</p>
      )}
    </div>
  );
}

export default function App() {
  const [token, setToken] = useState(null);
  const [email, setEmail] = useState("");
  const [items, setItems] = useState([]);
  const [current, setCurrent] = useState(null); // { video, playUrl }
  const [uploading, setUploading] = useState(false);
  const [tier, setTier] = useState("free");
  const fileRef = useRef(null);
  const api = token ? makeApi(token) : null;

  async function refresh() {
    setItems((await api.list()).items || []);
  }

  async function handleLogin(t, mail) {
    setToken(t);
    setEmail(mail);
    setItems((await makeApi(t).list()).items || []);
  }

  async function doUpload(e) {
    const file = e.target.files[0];
    e.target.value = ""; // cho phép chọn lại cùng một file
    if (!file) return;
    setUploading(true);
    try {
      const { uploadUrl } = await api.createUpload(file.name, tier);
      await fetch(uploadUrl, { method: "PUT", body: file }); // PUT thẳng lên S3 (presigned)
      await refresh();
    } finally {
      setUploading(false);
    }
  }

  async function watch(video) {
    const r = await api.playback(video.videoID);
    if (!r.playbackUrl) { await refresh(); return; } // 409: chưa ready -> đồng bộ lại trạng thái
    setCurrent({ video, playUrl: r.playbackUrl });
  }

  function signOut() {
    setToken(null);
    setEmail("");
    setItems([]);
    setCurrent(null);
  }

  if (!token) return <Login onLogin={handleLogin} />;

  return (
    <>
      <header className="global-nav">
        <div className="global-nav-inner">
          <span className="wordmark">StreamForge</span>
          <div className="nav-user">
            <span className="nav-email">{email}</span>
            <button className="btn-dark-utility" onClick={signOut}>Sign out</button>
          </div>
        </div>
      </header>

      <nav className="subnav">
        <div className="subnav-inner">
          <span className="subnav-title">Library</span>
          <div className="subnav-actions">
            <button className="text-link" onClick={refresh}>Refresh</button>
            <select className="tier-select" value={tier} onChange={(e) => setTier(e.target.value)} aria-label="Upload tier">
              <option value="free">Free</option>
              <option value="premium">Premium</option>
            </select>
            <button className="btn-pill" onClick={() => fileRef.current.click()} disabled={uploading}>
              {uploading ? "Uploading…" : "Upload video"}
            </button>
            <input ref={fileRef} type="file" accept="video/*" onChange={doUpload} hidden />
          </div>
        </div>
      </nav>

      {current && (
        <Player
          key={current.video.videoID}
          video={current.video}
          playUrl={current.playUrl}
          onClose={() => setCurrent(null)}
          onRefresh={() => api.playback(current.video.videoID)}
        />
      )}

      <main className="library">
        {items.length === 0 ? (
          <div className="empty">
            <h2 className="empty-headline">No videos yet.</h2>
            <p className="empty-copy">Upload a video and it will appear here, ready to stream in every quality.</p>
            <button className="btn-pill btn-pill-lg" onClick={() => fileRef.current.click()} disabled={uploading}>
              {uploading ? "Uploading…" : "Upload video"}
            </button>
          </div>
        ) : (
          <div className="library-grid">
            {items.map((v) => (
              <VideoCard key={v.videoID} video={v} onPlay={() => watch(v)} />
            ))}
          </div>
        )}
      </main>

      <footer className="footer">
        <div className="footer-inner">
          <p className="footer-line">StreamForge — a self-study AWS streaming pipeline.</p>
          <p className="footer-line">Uploads land in S3, transcode to HLS on EKS, and stream through CloudFront.</p>
        </div>
      </footer>
    </>
  );
}
