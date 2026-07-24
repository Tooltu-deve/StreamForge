export function makeApi(idToken) {
  const h = { Authorization: `Bearer ${idToken}`, "Content-Type": "application/json" };
  return {
    list: () => fetch("/api/catalog", { headers: h }).then((r) => r.json()),
    createUpload: (filename) =>
      fetch("/api/upload", { method: "POST", headers: h, body: JSON.stringify({ filename }) }).then((r) => r.json()),
    playback: (id) => fetch(`/api/playback/${id}`, { headers: h }).then((r) => r.json()),
  };
}
