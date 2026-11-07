const COPY = {
  en: {
    pill: "Online",
    eyebrow: "Dummy site for DR day",
    headline: "The dummy VM is up.",
    lede: "A small page you can screenshot. No login, no database, nothing to babysit.",
    proof: "This machine",
    host: "Host",
    address: "Address",
    time: "Time",
    role: "Role",
    site: "Site",
    uptime: "Uptime",
    fingerprint: "A little pattern from the hostname, so the primary and DR boxes look different.",
    requests: "Requests",
    pid: "Process",
    python: "Runtime",
    health: "Health",
    whyTitle: "Why this is here",
    whyBody: "You recover a VM, then someone asks if a website actually answers. Drop this on the dummy box, open it, take the screenshot.",
    why1: "Just Python. Nothing extra to install.",
    why2: "/health for monitors, /api/status for the raw details.",
    why3: "One setup script on Linux.",
    why4: "Nothing private on this page. Fine to share.",
    down: "Offline",
  },
  id: {
    pill: "Online",
    eyebrow: "Situs dummy buat hari DR",
    headline: "VM dummy-nya hidup.",
    lede: "Halaman kecil yang bisa di-screenshot. Tanpa login, tanpa database, tidak ada yang perlu dirawat.",
    proof: "Mesin ini",
    host: "Host",
    address: "Alamat",
    time: "Waktu",
    role: "Peran",
    site: "Situs",
    uptime: "Uptime",
    fingerprint: "Pola kecil dari hostname, jadi mesin primary dan DR kelihatan beda.",
    requests: "Request",
    pid: "Proses",
    python: "Runtime",
    health: "Health",
    whyTitle: "Kenapa ini ada",
    whyBody: "VM-nya sudah recover, lalu ada yang tanya apakah web-nya benar-benar jawab. Taruh ini di dummy, buka, ambil screenshot.",
    why1: "Cuma Python. Tidak perlu install apa-apa.",
    why2: "/health buat monitor, /api/status kalau butuh datanya mentah.",
    why3: "Satu skrip setup di Linux.",
    why4: "Tidak ada data pribadi di sini. Aman dibagi.",
    down: "Offline",
  },
};

const $ = (id) => document.getElementById(id);
let lang = localStorage.getItem("beacon-lang") || "en";
let lastUnix = 0;

function isDown() {
  return $("live-pill").classList.contains("is-down");
}

function applyLang() {
  const pack = COPY[lang] || COPY.en;
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-i18n]").forEach((node) => {
    const key = node.getAttribute("data-i18n");
    if (pack[key]) node.textContent = pack[key];
  });
  document.querySelectorAll("[data-lang]").forEach((btn) => {
    btn.classList.toggle("is-on", btn.getAttribute("data-lang") === lang);
  });
  if (lastUnix) setDown(isDown());
}

function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function drawIdenticon(seed) {
  const canvas = $("identicon");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const n = 5;
  const cell = 10;
  const gap = 2;
  const size = n * cell;
  canvas.width = size;
  canvas.height = size;
  const h = hash(seed || "beacon");
  ctx.fillStyle = "#121016";
  ctx.fillRect(0, 0, size, size);
  const palette = ["#e0b56a", "#7ec49d", "#f3eee6"];
  for (let y = 0; y < n; y += 1) {
    for (let x = 0; x < 3; x += 1) {
      const on = ((h >>> (y * 3 + x)) & 1) === 1;
      if (!on) continue;
      ctx.fillStyle = palette[(h >>> (x * 4 + y)) % palette.length];
      ctx.fillRect(x * cell, y * cell, cell - gap, cell - gap);
      ctx.fillRect((n - 1 - x) * cell, y * cell, cell - gap, cell - gap);
    }
  }
}

function formatUptime(seconds) {
  const s = Math.max(0, Number(seconds) || 0);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}h ${m}m ${sec}s`;
  if (m > 0) return `${m}m ${sec}s`;
  return `${sec}s`;
}

function setDown(offline) {
  const pack = COPY[lang] || COPY.en;
  document.querySelectorAll(".live").forEach((el) => {
    el.classList.toggle("is-down", offline);
  });
  document.querySelectorAll("[data-i18n='pill']").forEach((el) => {
    el.textContent = offline ? pack.down : pack.pill;
  });
  $("val-health").textContent = offline ? pack.down : "200 OK";
}

async function refresh() {
  try {
    const res = await fetch("/api/status", { cache: "no-store" });
    if (!res.ok) throw new Error("bad status");
    const data = await res.json();
    lastUnix = data.unix || Math.floor(Date.now() / 1000);
    $("val-host").textContent = data.hostname || "unknown";
    $("val-ip").textContent = (data.ips && data.ips[0]) || "127.0.0.1";
    $("val-role").textContent = data.role || "dummy";
    $("val-site").textContent = data.site_name || "Beacon";
    $("val-uptime").textContent = formatUptime(data.uptime_seconds);
    $("val-req").textContent = Number(data.requests || 0).toLocaleString();
    $("val-pid").textContent = `pid ${data.pid}`;
    $("val-py").textContent = `Python ${data.python}`;
    $("val-time").textContent = new Date(lastUnix * 1000).toLocaleString();
    drawIdenticon(data.hostname);
    setDown(false);
  } catch (err) {
    setDown(true);
  }
}

document.querySelectorAll("[data-lang]").forEach((btn) => {
  btn.addEventListener("click", () => {
    lang = btn.getAttribute("data-lang");
    localStorage.setItem("beacon-lang", lang);
    applyLang();
  });
});

applyLang();
refresh();
setInterval(refresh, 3000);
setInterval(() => {
  if (!lastUnix) return;
  lastUnix += 1;
  $("val-time").textContent = new Date(lastUnix * 1000).toLocaleString();
}, 1000);
