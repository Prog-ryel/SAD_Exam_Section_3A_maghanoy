import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const { SUPABASE_URL, SUPABASE_ANON_KEY } = window.APP_CONFIG || {};
const sb = createClient(SUPABASE_URL || "https://invalid.local", SUPABASE_ANON_KEY || "missing");
if (!SUPABASE_URL || /YOUR-PROJECT/i.test(SUPABASE_URL)) setTimeout(() => msg("config.js still has placeholder values. Save config.js and hard refresh (Ctrl+F5).", true), 0);
const $ = (id) => document.getElementById(id);
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const cls = (v) => esc(String(v).replace(/ /g, "-"));
const fmt = (t) => new Date(t).toLocaleString("en-PH", { timeZone: "Asia/Manila", hour12: false });
let me = null, programs = [];

function msg(text, err = false) {
  const m = $("msg"); m.textContent = text; m.className = "show" + (err ? " err" : "");
  if (!err) setTimeout(() => (m.className = ""), 4000);
}
const friendly = (m) => {
  if (/row-level security.*submissions/i.test(m)) return "Submission denied: you are not assigned to a program yet, or this term is already submitted and not Returned. Ask Scholarship Staff to assign your program.";
  if (/duplicate key|unique/i.test(m)) return "Duplicate: you already submitted this academic year and semester.";
  if (/gwa/i.test(m) && /check/i.test(m)) return "GWA must be between 1.00 and 5.00.";
  if (/violates check constraint/i.test(m)) return "Invalid value: counts must be 0 or more and the grade-document reference is required.";
  return m;
};
const run = async (p, ok) => { const { data, error } = await p; if (error) { msg(friendly(error.message), true); return null; } if (ok) msg(ok); return data ?? true; };

// ---- Auth ----
$("btn-login").onclick = async () => {
  const { error } = await sb.auth.signInWithPassword({ email: $("email").value, password: $("password").value });
  if (error) return msg(error.message, true);
  boot();
};
$("btn-signup").onclick = async () => {
  const sid = $("reg-sid").value.trim(), name = $("reg-name").value.trim();
  if (!sid || !name) return msg("Student ID and Full name are required to register.", true);
  const { data, error } = await sb.auth.signUp({ email: $("reg-email").value, password: $("reg-password").value, options: { data: { student_id: sid, full_name: name } } });
  if (error) return msg(error.message, true);
  if (data.session) return boot();
  showAuth(false);
  msg("Registered. Confirm via the email link if required, then log in. Staff will assign your program.");
};
function showAuth(reg) { $("login").hidden = reg; $("register").hidden = !reg; }
$("go-register").onclick = (e) => { e.preventDefault(); showAuth(true); };
$("go-login").onclick = (e) => { e.preventDefault(); showAuth(false); };
$("btn-logout").onclick = async () => { await sb.auth.signOut(); location.reload(); };

async function boot() {
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return;
  let { data: prof, error: perr } = await sb.from("profiles").select("*").eq("id", user.id).maybeSingle();
  if (perr) { msg("Profile lookup failed: " + perr.message + " (did you run 001_schema.sql?)", true); return; }
  const md = user.user_metadata || {};
  if (!prof && md.student_id && md.full_name) {   // first login after self-registration
    const r = await sb.from("profiles").insert({ id: user.id, role: "scholar", student_id: md.student_id, full_name: md.full_name }).select().single();
    if (r.error) { msg(r.error.message, true); return; }
    prof = r.data;
  }
  if (!prof) { msg("No profile yet. Ask Scholarship Staff to register you.", true); await sb.auth.signOut(); return; }
  me = prof;
  programs = (await run(sb.from("programs").select("*").order("id"))) || [];
  $("login").hidden = true; $("register").hidden = true; $("topbar").hidden = false;
  $("who").textContent = `${prof.full_name} (${prof.role})`;
  if (prof.role === "staff") { $("staff").hidden = false; initStaff(); } else { $("scholar").hidden = false; initScholar(); }
}

// ---- Scholar ----
async function initScholar() {
  const { data: a } = await sb.from("scholar_assignments").select("program_id,award_status").eq("scholar_id", me.id).maybeSingle();
  const p = programs.find((x) => x.id === a?.program_id);
  $("sch-program").textContent = p ? `Program: ${p.name} | Award: ${a.award_status} | Deadline: ${fmt(p.deadline)} Manila` : "";
  const assigned = !!p;
  $("notice").hidden = assigned;
  $("notice").textContent = "You are registered but not assigned to a scholarship program yet. Scholarship Staff must assign Merit or Community before you can submit grades.";
  [...$("sub-form").elements].forEach((el) => (el.disabled = !assigned));
  loadMine();
}
async function loadMine() {
  const rows = (await run(sb.from("submissions").select("*").order("submitted_at", { ascending: false }))) || [];
  $("my-subs").innerHTML = `<table><tr><th>AY/Sem</th><th>GWA</th><th>Units</th><th>F/INC/D</th><th>Submitted</th><th>Verification</th><th>Compliance</th><th>Renewal</th><th></th></tr>` +
    rows.map((r) => `<tr><td>${esc(r.academic_year)} / ${r.semester}</td><td>${r.gwa}</td><td>${r.units}</td>
    <td>${r.failed_count}/${r.incomplete_count}/${r.dropped_count}</td><td>${fmt(r.submitted_at)}</td>
    <td class="${cls(r.verification_status)}">${esc(r.verification_status)}${r.return_reason ? `<br><small>Reason: ${esc(r.return_reason)}</small>` : ""}</td>
    <td class="${cls(r.compliance_result)}">${esc(r.compliance_result)}${r.deficiency_reasons?.length ? `<br><small>${esc(r.deficiency_reasons.join("; "))}</small>` : ""}</td>
    <td>${esc(r.renewal_decision)}${r.decision_note ? `<br><small>${esc(r.decision_note)}</small>` : ""}</td>
    <td>${r.verification_status === "Returned" ? `<button class="sm" data-fill='${esc(JSON.stringify(r))}'>Resubmit</button>` : ""}</td></tr>`).join("") + `</table>`;
  document.querySelectorAll("[data-fill]").forEach((b) => (b.onclick = () => {
    const r = JSON.parse(b.dataset.fill), f = $("sub-form");
    for (const k of ["academic_year", "semester", "gwa", "units", "failed_count", "incomplete_count", "dropped_count", "evidence_ref"]) f[k].value = r[k] ?? "";
    msg("Form loaded. Correct the values and press Submit to resubmit.");
  }));
}
$("sub-form").onsubmit = async (e) => {
  e.preventDefault();
  const f = new FormData(e.target), v = Object.fromEntries(f);
  for (const k of ["semester", "units", "failed_count", "incomplete_count", "dropped_count"]) v[k] = parseInt(v[k], 10);
  v.gwa = parseFloat(v.gwa);
  const { data: ex } = await sb.from("submissions").select("id,verification_status").eq("academic_year", v.academic_year).eq("semester", v.semester).maybeSingle();
  let res;
  if (ex) {
    if (ex.verification_status !== "Returned") return msg("Duplicate: this term was already submitted and is not Returned.", true);
    res = await run(sb.from("submissions").update(v).eq("id", ex.id), "Resubmitted.");
  } else res = await run(sb.from("submissions").insert({ ...v, scholar_id: me.id }), "Submitted.");
  if (res) loadMine();
};

// ---- Staff ----
function initStaff() {
  for (const p of programs) {
    $("reg-program").add(new Option(p.name, p.name)); $("f-prog").add(new Option(p.name, p.name));
  }
  $("btn-refresh").onclick = loadStaff;
  ["q", "f-prog", "f-comp"].forEach((id) => ($(id).oninput = loadStaff));
  loadStaff();
}
$("reg-form").onsubmit = async (e) => {
  e.preventDefault();
  const v = Object.fromEntries(new FormData(e.target));
  if (await run(sb.rpc("register_scholar", { p_email: v.email, p_student_id: v.student_id, p_full_name: v.full_name, p_program: v.program }), "Scholar registered/assigned.")) { e.target.reset(); loadStaff(); }
};
async function loadStaff() {
  const ay = $("f-ay").value, sem = parseInt($("f-sem").value, 10);
  const [subs, asg] = await Promise.all([
    run(sb.from("submissions").select("*, profiles(student_id,full_name)").eq("academic_year", ay).eq("semester", sem)),
    run(sb.from("scholar_assignments").select("scholar_id,program_id,award_status"))]);
  if (!subs || !asg) return;
  const profs = (await run(sb.from("profiles").select("id,student_id,full_name").eq("role", "scholar").order("student_id"))) || [];
  $("scholars").innerHTML = profs.length ? `<table><tr><th>Student ID</th><th>Name</th><th>Program</th><th>Assign</th></tr>` + profs.map((p) => {
    const a = asg.find((x) => x.scholar_id === p.id), cur = programs.find((x) => x.id === a?.program_id)?.name;
    return `<tr><td>${esc(p.student_id)}</td><td>${esc(p.full_name)}</td><td>${esc(cur ?? "Not assigned")}</td>
    <td class="row"><select id="as-${p.id}">${programs.map((x) => `<option ${x.name === cur ? "selected" : ""}>${esc(x.name)}</option>`).join("")}</select>
    <button class="sm" data-assign="${p.id}">Assign</button></td></tr>`;
  }).join("") + `</table>` : "<small>No registered scholars yet.</small>";
  document.querySelectorAll("[data-assign]").forEach((b) => (b.onclick = async () => {
    if (await run(sb.rpc("assign_program", { p_scholar: b.dataset.assign, p_program: $("as-" + b.dataset.assign).value }), "Program assigned.")) loadStaff();
  }));
  const progOf = (sid) => programs.find((p) => p.id === asg.find((a) => a.scholar_id === sid)?.program_id)?.name ?? "-";
  const c = (fn) => subs.filter(fn).length;
  $("totals").innerHTML = [["Assigned", asg.length], ["Pending", c((s) => s.verification_status === "Pending")],
  ["Compliant", c((s) => s.compliance_result === "Compliant")], ["With Deficiency", c((s) => s.compliance_result === "With Deficiency")]]
    .map(([k, n]) => `<div class="stat"><b>${n}</b>${k}</div>`).join("");
  const q = $("q").value.toLowerCase(), fp = $("f-prog").value, fc = $("f-comp").value;
  const rows = subs.filter((s) => (!q || `${s.profiles?.student_id} ${s.profiles?.full_name}`.toLowerCase().includes(q)) &&
    (!fp || progOf(s.scholar_id) === fp) && (!fc || s.compliance_result === fc))
    .sort((a, b) => (a.profiles?.student_id || "").localeCompare(b.profiles?.student_id || ""));
  $("staff-subs").innerHTML = `<table><tr><th>ID</th><th>Name</th><th>Program</th><th>GWA/Units/F/INC/D</th><th>Submitted (Manila)</th><th>Verification</th><th>Compliance</th><th>Renewal</th><th>Actions</th></tr>` +
    rows.map((s) => `<tr><td>${esc(s.profiles?.student_id)}</td><td>${esc(s.profiles?.full_name)}</td><td>${esc(progOf(s.scholar_id))}</td>
    <td>${s.gwa}/${s.units}/${s.failed_count}/${s.incomplete_count}/${s.dropped_count}</td><td>${fmt(s.submitted_at)}</td>
    <td class="${cls(s.verification_status)}">${esc(s.verification_status)}</td>
    <td class="${cls(s.compliance_result)}">${esc(s.compliance_result)}</td><td>${esc(s.renewal_decision)}</td>
    <td class="row">
    ${s.verification_status === "Pending" ? `<button class="sm" data-act="verify" data-id="${s.id}">Verify</button><button class="sm ghost" data-act="return" data-id="${s.id}">Return</button>` : ""}
    ${s.verification_status === "Verified" ? `<button class="sm" data-act="eval" data-id="${s.id}">Evaluate</button>` : `<small>Evaluation blocked</small>`}
    ${s.verification_status === "Verified" && s.compliance_result !== "Not Evaluated" ? `<button class="sm" data-act="approve" data-id="${s.id}">Approve</button><button class="sm ghost" data-act="hold" data-id="${s.id}">Hold</button>` : ""}
    <button class="sm ghost" data-act="hist" data-id="${s.id}">History</button></td></tr>`).join("") + `</table>`;
  document.querySelectorAll("[data-act]").forEach((b) => (b.onclick = () => act(b.dataset.act, b.dataset.id)));
}
async function act(a, id) {
  if (a === "verify") { if (await run(sb.rpc("verify_submission", { p_id: id, p_action: "Verified" }), "Verified.")) loadStaff(); }
  else if (a === "return") {
    const r = prompt("Return reason (required):"); if (!r) return msg("Reason required.", true);
    if (await run(sb.rpc("verify_submission", { p_id: id, p_action: "Returned", p_reason: r }), "Returned.")) loadStaff();
  } else if (a === "eval") {
    const r = await run(sb.rpc("evaluate_submission", { p_id: id })); if (!r) return;
    $("detail").hidden = false;
    $("detail").innerHTML = `<h2>Evaluation: <span class="${cls(r.result)}">${esc(r.result)}</span></h2><table><tr><th>Check</th><th>Rule</th><th>Actual</th><th>Result</th></tr>` +
      r.checks.map((c) => `<tr><td>${esc(c.check)}</td><td>${esc(c.rule)}</td><td>${esc(c.actual)}</td><td class="${c.pass ? "pass" : "fail"}">${c.pass ? "PASS" : "FAIL"}</td></tr>`).join("") +
      `</table><p>${r.reasons.length ? "Deficiency reasons: " + esc(r.reasons.join("; ")) : "No deficiencies."}</p><small>Award status is not changed automatically.</small>`;
    loadStaff();
  } else if (a === "approve" || a === "hold") {
    const n = prompt("Decision note (required):"); if (!n) return msg("Note required.", true);
    if (await run(sb.rpc("record_decision", { p_id: id, p_decision: a === "approve" ? "Approved" : "Held", p_note: n }), "Decision recorded.")) loadStaff();
  } else if (a === "hist") {
    const h = (await run(sb.from("audit_log").select("*").eq("submission_id", id).order("created_at"))) || [];
    $("detail").hidden = false;
    $("detail").innerHTML = `<h2>History</h2><table><tr><th>When (Manila)</th><th>Action</th><th>Old</th><th>New</th><th>Note</th></tr>` +
      h.map((x) => `<tr><td>${fmt(x.created_at)}</td><td>${esc(x.action)}</td><td>${esc(x.old_value)}</td><td>${esc(x.new_value)}</td><td>${esc(x.note)}</td></tr>`).join("") + `</table>`;
  }
}
boot();
