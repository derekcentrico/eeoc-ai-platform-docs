/* EEOC AI Platform — Showcase Site Scripts */

/* ---- Navigation active state ---- */
document.addEventListener('DOMContentLoaded', () => {
  const currentPage = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-links a').forEach(link => {
    const href = link.getAttribute('href');
    if (href === currentPage || (currentPage === '' && href === 'index.html')) {
      link.classList.add('active');
    }
  });

  initChatSimulations();
  initArchDiagram();
  initFlowSteps();
  initCounters();
});

/* ---- Typewriter effect for AI chat ---- */
function typewriter(element, text, speed = 18, callback) {
  let i = 0;
  element.textContent = '';
  const cursor = document.createElement('span');
  cursor.className = 'typing-cursor';
  element.appendChild(cursor);

  function type() {
    if (i < text.length) {
      element.insertBefore(document.createTextNode(text.charAt(i)), cursor);
      i++;
      setTimeout(type, speed + Math.random() * 12);
    } else {
      cursor.remove();
      if (callback) callback();
    }
  }
  type();
}

/* ---- Chat simulation ---- */
function initChatSimulations() {
  document.querySelectorAll('.chat-panel').forEach(panel => {
    const input = panel.querySelector('.chat-input');
    const sendBtn = panel.querySelector('.chat-send');
    const messages = panel.querySelector('.chat-messages');
    const chatId = panel.dataset.chatId;

    if (!input || !sendBtn) return;

    const responses = getChatResponses(chatId);
    let responseIndex = 0;

    function sendMessage() {
      const text = input.value.trim();
      if (!text) return;

      const userMsg = document.createElement('div');
      userMsg.className = 'chat-msg user';
      userMsg.textContent = text;
      messages.appendChild(userMsg);
      input.value = '';

      setTimeout(() => {
        const aiMsg = document.createElement('div');
        aiMsg.className = 'chat-msg ai';

        const contentSpan = document.createElement('span');
        contentSpan.className = 'ai-content';
        aiMsg.appendChild(contentSpan);

        messages.appendChild(aiMsg);
        messages.scrollTop = messages.scrollHeight;

        const response = responses[responseIndex % responses.length];
        responseIndex++;

        typewriter(contentSpan, response.text, 14, () => {
          const meta = document.createElement('div');
          meta.className = 'msg-meta';
          meta.innerHTML = `<span>HMAC-SHA256 verified</span><span>Audit ID: ${response.auditId}</span><span>Human review required</span>`;
          aiMsg.appendChild(meta);
          messages.scrollTop = messages.scrollHeight;
        });
      }, 600);
    }

    sendBtn.addEventListener('click', sendMessage);
    input.addEventListener('keydown', e => {
      if (e.key === 'Enter') sendMessage();
    });

    // Auto-populate suggested queries
    panel.querySelectorAll('.chat-suggest').forEach(btn => {
      btn.addEventListener('click', () => {
        input.value = btn.textContent;
        sendMessage();
      });
    });
  });
}

function getChatResponses(chatId) {
  const responses = {
    'analytics': [
      {
        text: 'In FY2025 Q3, the ADR program resolved 847 mediations across 15 district offices. The national settlement rate was 72.3%, up 4.1 percentage points from Q2. Philadelphia (81.2%), Chicago (79.8%), and Dallas (78.4%) led in settlement rates. Average time-to-resolution decreased from 47 days to 41 days.',
        auditId: 'aud-7f3a9e2c'
      },
      {
        text: 'Race-based charges accounted for 34.2% of mediations (290 cases), followed by disability (22.1%, 187 cases) and sex/gender (18.7%, 158 cases). Settlement rates were highest for age-based charges (78.9%) and lowest for retaliation claims (64.1%). Multi-basis charges represented 15.3% of the docket.',
        auditId: 'aud-2b8c4d1e'
      },
      {
        text: 'The top 5 offices by caseload were: New York (112 cases), Los Angeles (98), Chicago (87), Houston (76), and Atlanta (71). Resource utilization ranged from 68% (Phoenix) to 94% (New York). Three offices — Seattle, Denver, and Miami — are below the 70% utilization threshold and may have capacity for case redistribution.',
        auditId: 'aud-9d5f7a3b'
      }
    ],
    'triage': [
      {
        text: 'Based on the charge narrative and statutory indicators, this charge is classified as: Priority A (Full Investigation Recommended). Basis: Race + Retaliation (dual-filed). Key factors: temporal proximity (termination within 14 days of complaint), pattern evidence cited (3 prior complaints), and documentary evidence referenced.',
        auditId: 'aud-4e2a8c6f'
      },
      {
        text: 'Routing recommendation: Assign to Mediation Track. Respondent has participated in 6 prior EEOC mediations with a 67% settlement rate. Charging party indicated willingness to mediate in the intake questionnaire. Estimated resolution timeline: 35-45 days based on similar case profiles.',
        auditId: 'aud-1c7b3d9a'
      }
    ]
  };
  return responses[chatId] || responses['analytics'];
}

/* ---- Architecture diagram interactivity ---- */
function initArchDiagram() {
  document.querySelectorAll('.arch-node').forEach(node => {
    node.addEventListener('click', () => {
      document.querySelectorAll('.arch-node').forEach(n => n.classList.remove('active'));
      node.classList.add('active');

      const detailPanel = document.getElementById('arch-detail');
      if (detailPanel) {
        const key = node.dataset.component;
        detailPanel.innerHTML = getComponentDetail(key);
        detailPanel.style.display = 'block';
      }
    });
  });
}

function getComponentDetail(key) {
  const details = {
    'arc': '<h4>ARC Legacy System</h4><p>The Agency Record Center stores charge data, investigation records, and enforcement history. EEOC\'s system of record for all discrimination charges filed under Title VII, ADA, ADEA, EPA, and GINA.</p><p class="text-muted mt-1">Read-only integration via ARC Integration API. No direct access from applications.</p>',
    'arc-api': '<h4>ARC Integration API</h4><p>FastAPI gateway that translates ARC\'s SOAP/REST interfaces into a clean, authenticated REST API. All charge data flows through this single service — no other application calls ARC directly.</p><p class="step-detail mt-1">GET /arc/v1/mediation/eligible-cases<br>GET /arc/v1/enforcement/cases/{charge_number}</p>',
    'mcp-hub': '<h4>MCP Hub (API Management)</h4><p>Azure Functions aggregator that discovers and catalogs tools exposed by each spoke application. Enables cross-application tool invocation via the Model Context Protocol (JSON-RPC 2.0 over HTTP).</p><p class="step-detail mt-1">GET /api/tools — merged catalog from all spokes<br>POST /api/tools/refresh — on-demand refresh</p>',
    'adr': '<h4>ADR Portal</h4><p>Mediation case management for the Office of Federal Operations. Handles case intake from ARC, mediator assignment, scheduling, document management, AI-assisted agreement drafting, e-signature, and disposition tracking.</p><p class="text-muted mt-1">Status: <span class="text-success">Production Testing</span> — deployed on Azure App Service.</p>',
    'triage': '<h4>OFS Triage</h4><p>Charge intake and program routing. AI-powered classification determines investigation priority, identifies applicable statutes, and recommends the optimal resolution track (mediation, investigation, or conciliation).</p><p class="text-muted mt-1">Status: Development complete, pending deployment.</p>',
    'trial-tool': '<h4>OGC Trial Tool</h4><p>Attorney trial preparation platform for the Office of General Counsel. Document analysis, case timeline construction, witness management, and AI-assisted legal research across the full enforcement case file.</p><p class="text-muted mt-1">Status: Development complete, pending deployment.</p>',
    'ochco': '<h4>OCHCO Benefits Validation</h4><p>Coding validation and overpayment detection for the Office of the Chief Human Capital Officer. Cross-references OPM benefit rules against personnel action coding to identify discrepancies before they become overpayments.</p><p class="text-muted mt-1">Status: In development.</p>',
    'dashboard': '<h4>Data Analytics Platform (UDAP)</h4><p>Cross-program analytics combining charge data, mediation outcomes, investigation metrics, and operational KPIs. Natural language query interface, automated narrative generation, and executive dashboards.</p><p class="text-muted mt-1">Components: data-middleware (ETL pipeline), ai-assistant (NL query), Superset (dashboards), JupyterHub (ad-hoc analysis).</p>',
  };
  return details[key] || '<p>Select a component to see details.</p>';
}

/* ---- Flow step animation ---- */
function initFlowSteps() {
  const steps = document.querySelectorAll('.flow-step');
  if (!steps.length) return;

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('active');
      }
    });
  }, { threshold: 0.5 });

  steps.forEach(step => observer.observe(step));
}

/* ---- Counter animation ---- */
function initCounters() {
  document.querySelectorAll('.counter').forEach(el => {
    const target = parseInt(el.dataset.target, 10);
    const duration = 1500;
    const step = target / (duration / 16);
    let current = 0;

    const observer = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) {
        const timer = setInterval(() => {
          current += step;
          if (current >= target) {
            current = target;
            clearInterval(timer);
          }
          el.textContent = Math.floor(current).toLocaleString();
        }, 16);
        observer.disconnect();
      }
    });
    observer.observe(el);
  });
}

/* ---- Tab switching ---- */
function switchTab(tabGroup, tabId) {
  document.querySelectorAll(`[data-tab-group="${tabGroup}"]`).forEach(panel => {
    panel.style.display = panel.id === tabId ? 'block' : 'none';
  });
  document.querySelectorAll(`[data-tab-target]`).forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tabTarget === tabId);
  });
}
