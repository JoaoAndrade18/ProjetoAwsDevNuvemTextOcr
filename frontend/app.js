const API = location.origin; // mesmo host via Nginx

async function listJobs(){
  const r = await fetch(`${API}/api/jobs/`, {headers:{Accept:'application/json'}});
  const data = await r.json();
  renderJobs(data.results || []);
}

function esc(s){ return (s||'').replace(/[<>&]/g, m => ({'<':'&lt;','>':'&gt;','&':'&amp;'}[m])); }

function renderJobs(jobs){
  const el = document.getElementById('jobs');
  if(!jobs.length){ el.innerHTML = '<div class="muted">Nenhum job.</div>'; return; }
  el.innerHTML = jobs.map(j => `
    <div class="row">
      <div>
        <strong>${esc(j.name)}</strong><br>
        <span class="muted">${j.id}</span><br>
        <span class="muted">${j.created_at}</span>
      </div>
      <div>
        <span>Total: ${j.total_items} · Concluídos: ${j.done_items}</span>
        <button onclick="openJob('${j.id}')">Abrir</button>
        <button onclick="delJob('${j.id}')">Excluir</button>
      </div>
    </div>
  `).join('<hr>');
}

async function openJob(id){
  document.getElementById('jobDetail').style.display='block';
  document.getElementById('jobId').textContent=id;
  await refreshJob(id);
  if(window._jobTimer) clearInterval(window._jobTimer);
  window._jobTimer = setInterval(()=>refreshJob(id), 4000);
}

async function refreshJob(id){
  const r = await fetch(`${API}/api/jobs/${id}/`, {headers:{Accept:'application/json'}});
  const j = await r.json();
  document.getElementById('jobInfo').textContent =
    `status=${j.status} · itens=${j.total_items} · done=${j.done_items}`;
  const items = (j.items || []).map(it => `
    <div class="card">
      <div><strong>Item:</strong> ${it.id} — status: ${it.status}</div>
      <div class="muted">S3: ${esc(it.s3_key||'-')}</div>
      <div class="mt8">
        <label>Texto extraído:</label>
        <pre>${esc(it.ocr_text||'')}</pre>
      </div>
    </div>`).join('');
  document.getElementById('items').innerHTML = items || '<div class="muted">Sem itens.</div>';
}

async function delJob(id){
  if(!confirm('Excluir este job?')) return;
  const r = await fetch(`${API}/api/jobs/${id}/`, {method:'DELETE'});
  if(r.ok){ listJobs(); document.getElementById('jobDetail').style.display='none'; }
}

document.getElementById('btnRefresh').onclick = listJobs;

document.getElementById('formUpload').addEventListener('submit', async (ev)=>{
  ev.preventDefault();
  const fd = new FormData(ev.target);
  const files = document.getElementById('images').files;
  for(const f of files) fd.append('images', f, f.name);
  const r = await fetch(`${API}/api/jobs/`, { method:'POST', body: fd });
  const msg = document.getElementById('uploadMsg');
  if(r.ok){
    const j = await r.json();
    msg.textContent = 'Job criado: '+j.id;
    listJobs(); openJob(j.id);
  }else{
    msg.textContent = 'Falha no upload';
  }
});

listJobs();
