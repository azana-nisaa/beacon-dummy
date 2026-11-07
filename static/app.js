const COPY = {
  en: {
    pill: "ONLINE",
    eyebrow: "Disaster recovery canary",
    headline: "If you can see this page, the dummy VM is alive.",
    lede: "Lightweight proof-of-life for failover tests. No database, no login, no blank “it works” screen — just a page you can actually screenshot for the report.",
    proof: "PROOF OF LIFE",
    host: "HOST",
    address: "ADDRESS",
    time: "TIME",
    role: "ROLE",
    site: "SITE",
    uptime: "UPTIME",
    fingerprint: "Hostname fingerprint — primary and DR boxes will not look the same.",
    requests: "Requests served",
    pid: "Process",
    python: "Runtime",
    health: "Health",
    whyTitle: "Why this exists",
    whyBody: "DR tests often recover a VM that nobody can prove is actually serving traffic. Beacon is a tiny public dummy: clone it, run one script, open a browser. If the beam is on, HTTP is working.",
    why1: "One Python file. No packages to install.",
    why2: "/health for load balancers, /api/status for JSON evidence.",
    why3: "Works as a systemd service on a Linux dummy VM.",
    why4: "Safe to share. There is nothing confidential on this page.",
    down: "UNREACHABLE",
    wait: "waiting",
  },
  id: {
    pill: "ONLINE",
    eyebrow: "Canary disaster recovery",
    headline: "Kalau halaman ini kebuka, VM dummy-nya hidup.",
    lede: "Bukti ringan buat latihan failover. Tanpa database, tanpa login, bukan halaman kosong — siap di-screenshot buat laporan DR.",
    proof: "BUKTI HIDUP",
    host: "HOST",
    address: "ALAMAT",
    time: "WAKTU",
    role: "PERAN",
    site: "SITUS",
    uptime: "UPTIME",
    fingerprint: "Sidik jari hostname — VM primary dan DR tidak akan tampak sama.",
    requests: "Request terlayani",
    pid: "Proses",
    python: "Runtime",
    health: "Health",
    whyTitle: "Kenapa ada ini",
    whyBody: "Tes DR sering recover VM tanpa bukti bahwa HTTP-nya benar-benar jalan. Beacon dummy kecil yang bisa di-clone, dijalankan satu skrip, lalu dibuka di browser. Kalau lampunya nyala, web-nya tembus.",
    why1: "Satu file Python. Tidak perlu install package.",
    why2: "/health buat load balancer, /api/status buat bukti JSON.",
    why3: "Siap jadi service systemd di Linux dummy VM.",
    why4: "Aman dibagi. Tidak ada data rahasia di halaman ini.",
    down: "TIDAK TERJANGKAU",
    wait: "menunggu",
  },
};

const $ = (id) => document.getElementById(id);
let lang = localStorage.getItem("beacon-lang") || "en";
let lastUnix = 0;

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
  ctx.fillStyle = "#070b16";
  ctx.fillRect(0, 0, size, size);
  const palette = ["#f5c16c", "#6ee7d2", "#e8edf7"];
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

function setDown(isDown) {
  const pack = COPY[lang] || COPY.en;
  $("live-pill").classList.toggle("is-down", isDown);
  $("live-pill").querySelector("[data-i18n='pill']").textContent = isDown ? pack.down : pack.pill;
  $("ticket-state").textContent = isDown ? pack.down : "ONLINE";
  $("val-health").textContent = isDown ? pack.down : "200 OK";
}

async function refresh() {
  try {
    const res = await fetch("/api/status", { cache: "no-store" });
    if (!res.ok) throw new Error("bad status");
    const data = await res.json();
    lastUnix = data.unix || Math.floor(Date.now() / 1000);
    $("val-host").textContent = data.hostname || "unknown";
    $("val-ip").textContent = (data.ips && data.ips[0]) || "127.0.0.1";
    $("val-role").textContent = (data.role || "dummy").toUpperCase();
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
