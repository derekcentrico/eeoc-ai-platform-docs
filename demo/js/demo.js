/* EEOC AI Platform — Demo Mockup Scripts */

document.addEventListener('DOMContentLoaded', () => {
  initToasts();
  initChat();
  initCounters();
});

/* ---- Toast / Explainer System ---- */
let toastQueue = [];
let toastTimer = null;

function initToasts() {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const toasts = container.dataset.toasts;
  if (!toasts) return;

  try {
    toastQueue = JSON.parse(toasts);
  } catch (e) {
    return;
  }

  let index = 0;
  function showNext() {
    if (index >= toastQueue.length) return;
    const t = toastQueue[index];
    addToast(t.type || '', t.title || '', t.text || '', t.duration || 8000);
    index++;
    toastTimer = setTimeout(showNext, (t.delay || 4000));
  }

  setTimeout(showNext, 2000);
}

function addToast(type, title, text, duration) {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const icons = {
    'info': 'bi-info-circle',
    'mcp': 'bi-diagram-3',
    'data': 'bi-database',
    '': 'bi-lightbulb'
  };

  const el = document.createElement('div');
  el.className = `toast toast-${type || 'info'}`;
  el.innerHTML = `
    <i class="bi ${icons[type] || icons['']} toast-icon"></i>
    <div class="toast-body">
      <div class="toast-title">${title}</div>
      <div class="toast-text">${text}</div>
    </div>
    <button class="toast-close" aria-label="Dismiss">&times;</button>
  `;

  el.querySelector('.toast-close').addEventListener('click', () => {
    el.style.opacity = '0';
    setTimeout(() => el.remove(), 200);
  });

  container.appendChild(el);

  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transition = 'opacity 0.3s';
    setTimeout(() => el.remove(), 300);
  }, duration);
}

/* ---- Chat Simulation ---- */
function initChat() {
  document.querySelectorAll('.chat-container').forEach(panel => {
    const input = panel.querySelector('.chat-input');
    const sendBtn = panel.querySelector('.chat-send');
    const messages = panel.querySelector('.chat-messages');
    const chatId = panel.dataset.chatId;
    if (!input || !sendBtn || !messages) return;

    const responses = getResponses(chatId);
    let idx = 0;

    function send() {
      const text = input.value.trim();
      if (!text) return;

      const userMsg = document.createElement('div');
      userMsg.className = 'msg msg-user';
      userMsg.textContent = text;
      messages.appendChild(userMsg);
      input.value = '';
      messages.scrollTop = messages.scrollHeight;

      setTimeout(() => {
        const aiMsg = document.createElement('div');
        aiMsg.className = 'msg msg-ai';
        const span = document.createElement('span');
        aiMsg.appendChild(span);
        messages.appendChild(aiMsg);
        messages.scrollTop = messages.scrollHeight;

        const r = responses[idx % responses.length];
        idx++;
        typewriter(span, r.text, 12, () => {
          const audit = document.createElement('div');
          audit.className = 'msg-audit';
          audit.innerHTML = `<span>HMAC-SHA256 verified</span><span>Audit ID: ${r.auditId}</span><span>Human review required</span>`;
          aiMsg.appendChild(audit);
          messages.scrollTop = messages.scrollHeight;
        });
      }, 500);
    }

    sendBtn.addEventListener('click', send);
    input.addEventListener('keydown', e => { if (e.key === 'Enter') send(); });

    panel.querySelectorAll('.chat-suggest').forEach(btn => {
      btn.addEventListener('click', () => { input.value = btn.textContent; send(); });
    });
  });
}

function typewriter(el, text, speed, cb) {
  let i = 0;
  el.textContent = '';
  const cursor = document.createElement('span');
  cursor.style.cssText = 'display:inline-block;width:2px;height:14px;background:var(--text-sec);animation:pulse 0.8s infinite;vertical-align:middle;margin-left:2px;';
  el.appendChild(cursor);
  function type() {
    if (i < text.length) {
      el.insertBefore(document.createTextNode(text.charAt(i)), cursor);
      i++;
      setTimeout(type, speed + Math.random() * 10);
    } else {
      cursor.remove();
      if (cb) cb();
    }
  }
  type();
}

function getResponses(id) {
  const r = {
    'analytics': [
      { text: 'In FY2025 Q3, the ADR program resolved 847 mediations across 15 district offices. The national settlement rate was 72.3%, up 4.1 percentage points from Q2. Philadelphia (81.2%), Chicago (79.8%), and Dallas (78.4%) led in settlement rates. Average resolution time decreased from 47 to 41 days.', auditId: 'ana-7f3a9e2c' },
      { text: 'Race-based charges accounted for 34.2% of mediations (290 cases), followed by disability (22.1%, 187 cases) and sex/gender (18.7%, 158 cases). Settlement rates were highest for age-based charges (78.9%) and lowest for retaliation claims (64.1%).', auditId: 'ana-2b8c4d1e' },
      { text: 'Phoenix (63.2%) and Los Angeles (66.4%) have the lowest settlement rates. Phoenix saw a 28% caseload increase without additional staffing — 34 cases per mediator versus the 22-case national average. Recommendation: consider temporary mediator reassignment from Denver (68% utilization) and Seattle (71%) to reduce the backlog.', auditId: 'ana-9d5f7a3b' }
    ],
    'triage': [
      { text: 'Based on the charge narrative and statutory indicators, this charge is classified as Priority A — Full Investigation Recommended. Basis: Race + Retaliation (dual-filed). Key factors: temporal proximity (termination within 14 days of complaint), pattern evidence (3 prior internal complaints), and documentary evidence referenced.', auditId: 'clf-4e2a8c6f' },
      { text: 'Routing recommendation: Mediation Track. Respondent participated in 4 prior EEOC mediations with 75% settlement rate. Charging party indicated willingness to mediate. Estimated resolution timeline: 35-45 days based on similar case profiles in this district.', auditId: 'clf-1c7b3d9a' }
    ],
    'trial': [
      { text: 'Cross-referencing Exhibit B (performance reviews) against Deposition — J. Williams: Williams states the charging party "consistently exceeded expectations" (Dep. p.18, line 4), which directly contradicts the respondent\'s claim of "performance concerns" cited in the termination letter (Exhibit C). This discrepancy spans three document sources and strengthens the pretext argument.', auditId: 'tri-6b3d9f4a' },
      { text: 'Timeline analysis reveals a 14-day gap between the internal EEO complaint (Jan 12) and the promotion denial (Jan 26). The position was posted internally on Dec 15 with a Jan 20 close date. The hiring committee met Jan 24 — two days before the denial — but the complaint was filed before the committee meeting. This sequence supports temporal proximity for the retaliation claim.', auditId: 'tri-8e2c5a7d' }
    ],
    'benefits': [
      { text: 'Batch #2026-05-19 flagged 12 discrepancies out of 847 personnel actions reviewed (1.4% error rate). The highest-value finding is Action 702 for J. Thompson: retirement coded as FERS (Code C) instead of CSRS Offset (Code K). Based on the 1987 hire date and 6 years of prior military service credit, CSRS Offset eligibility criteria are met. The monthly payment difference is $2,340 — annualized potential overpayment of $28,080.', auditId: 'val-3c9f1d2a' },
      { text: 'Three additional FEGLI discrepancies detected in this batch: employees transferred between offices with mismatched life insurance codes. Original office coded Option B (5x salary), receiving office recorded Option A (1x salary). Premium difference: $47.20/pay period per employee. All three transfers occurred in the same pay period (PP 10), suggesting a systematic data entry error during the office consolidation.', auditId: 'val-7a4e2b8c' }
    ]
  };
  return r[id] || r['analytics'];
}

/* ---- Counter Animation ---- */
function initCounters() {
  document.querySelectorAll('.counter').forEach(el => {
    const target = parseFloat(el.dataset.target);
    const suffix = el.dataset.suffix || '';
    const prefix = el.dataset.prefix || '';
    const decimals = (el.dataset.decimals || '0') | 0;
    const duration = 1200;
    const step = target / (duration / 16);
    let current = 0;
    const observer = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting) {
        const timer = setInterval(() => {
          current += step;
          if (current >= target) { current = target; clearInterval(timer); }
          el.textContent = prefix + current.toFixed(decimals).replace(/\B(?=(\d{3})+(?!\d))/g, ',') + suffix;
        }, 16);
        observer.disconnect();
      }
    });
    observer.observe(el);
  });
}
