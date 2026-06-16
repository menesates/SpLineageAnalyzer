const state = {
  data: [],
  procedures: [],
  selectedProcedure: null,
  selectedColumn: null,
  procedureQuery: "",
  columnQuery: "",
  sourceKind: "",
  activeTab: "table",
};

const els = {
  loadStatus: document.querySelector("#loadStatus"),
  reloadButton: document.querySelector("#reloadButton"),
  errorPanel: document.querySelector("#errorPanel"),
  procedureSearch: document.querySelector("#procedureSearch"),
  procedureList: document.querySelector("#procedureList"),
  procedureCount: document.querySelector("#procedureCount"),
  selectedProcedureTitle: document.querySelector("#selectedProcedureTitle"),
  selectedProcedureFile: document.querySelector("#selectedProcedureFile"),
  columnSearch: document.querySelector("#columnSearch"),
  sourceKindFilter: document.querySelector("#sourceKindFilter"),
  columnTableBody: document.querySelector("#columnTableBody"),
  detailContent: document.querySelector("#detailContent"),
  kindChart: document.querySelector("#kindChart"),
  topObjects: document.querySelector("#topObjects"),
  tableTab: document.querySelector("#tableTab"),
  rawTab: document.querySelector("#rawTab"),
  tableView: document.querySelector("#tableView"),
  rawView: document.querySelector("#rawView"),
  rawJson: document.querySelector("#rawJson"),
  metrics: {
    files: document.querySelector("#metricFiles"),
    procedures: document.querySelector("#metricProcedures"),
    columns: document.querySelector("#metricColumns"),
    sources: document.querySelector("#metricSources"),
    branches: document.querySelector("#metricBranches"),
    operations: document.querySelector("#metricOperations"),
  },
};

els.reloadButton.addEventListener("click", () => loadData());
els.procedureSearch.addEventListener("input", (event) => {
  state.procedureQuery = event.target.value.trim().toLowerCase();
  renderProcedures();
});
els.columnSearch.addEventListener("input", (event) => {
  state.columnQuery = event.target.value.trim().toLowerCase();
  renderColumns();
});
els.sourceKindFilter.addEventListener("change", (event) => {
  state.sourceKind = event.target.value;
  renderColumns();
});
els.tableTab.addEventListener("click", () => switchTab("table"));
els.rawTab.addEventListener("click", () => switchTab("raw"));

loadData();

async function loadData() {
  setError("");
  els.loadStatus.textContent = "Yukleniyor...";

  try {
    const response = await fetch(`/output/lineage.json?ts=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`output/lineage.json okunamadi. HTTP ${response.status}`);
    }

    const data = await response.json();
    if (!Array.isArray(data)) {
      throw new Error("Beklenen JSON kok yapisi array degil.");
    }

    state.data = data;
    state.procedures = flattenProcedures(data);
    state.selectedProcedure = state.procedures[0] ?? null;
    state.selectedColumn = state.selectedProcedure?.outputColumns?.[0] ?? null;

    const loadedAt = new Date().toLocaleTimeString("tr-TR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    els.loadStatus.textContent = `${loadedAt} yüklendi`;
    els.rawJson.textContent = JSON.stringify(data, null, 2);

    renderAll();
  } catch (error) {
    state.data = [];
    state.procedures = [];
    state.selectedProcedure = null;
    state.selectedColumn = null;
    els.loadStatus.textContent = "Yukleme hatasi";
    setError(error instanceof Error ? error.message : String(error));
    renderAll();
  }
}

function flattenProcedures(files) {
  return files.flatMap((fileEntry, fileIndex) => {
    const procedures = Array.isArray(fileEntry.procedures) ? fileEntry.procedures : [];
    return procedures.map((procedure, procedureIndex) => ({
      ...procedure,
      __id: `${fileIndex}:${procedureIndex}:${procedure.name ?? "procedure"}`,
      __file: fileEntry.file ?? "",
      __diagnostics: [...(fileEntry.diagnostics ?? []), ...(procedure.diagnostics ?? [])],
    }));
  });
}

function renderAll() {
  renderMetrics();
  renderSourceKindOptions();
  renderProcedures();
  renderSelectedProcedure();
  renderColumns();
  renderDetail();
  renderAnalytics();
  switchTab(state.activeTab);
}

function renderMetrics() {
  const metrics = calculateMetrics(state.data);
  els.metrics.files.textContent = formatNumber(metrics.files);
  els.metrics.procedures.textContent = formatNumber(metrics.procedures);
  els.metrics.columns.textContent = formatNumber(metrics.columns);
  els.metrics.sources.textContent = formatNumber(metrics.sources);
  els.metrics.branches.textContent = formatNumber(metrics.branches);
  els.metrics.operations.textContent = formatNumber(metrics.operations);
}

function calculateMetrics(files) {
  const metrics = {
    files: files.length,
    procedures: 0,
    columns: 0,
    sources: 0,
    branches: 0,
    operations: 0,
  };

  for (const procedure of state.procedures) {
    metrics.procedures += 1;
    for (const column of procedure.outputColumns ?? []) {
      metrics.columns += 1;
      metrics.operations += (column.operations ?? []).length;
      metrics.branches += (column.branches ?? []).length;
      for (const source of getAllColumnSources(column)) {
        metrics.sources += countSourceTree(source);
      }
    }
  }

  return metrics;
}

function renderSourceKindOptions() {
  const kinds = new Set();
  for (const procedure of state.procedures) {
    for (const column of procedure.outputColumns ?? []) {
      for (const source of getAllColumnSources(column)) {
        collectKinds(source, kinds);
      }
    }
  }

  const current = state.sourceKind;
  els.sourceKindFilter.innerHTML = `<option value="">Hepsi</option>${[...kinds]
    .sort()
    .map((kind) => `<option value="${escapeHtml(kind)}">${escapeHtml(kind)}</option>`)
    .join("")}`;
  els.sourceKindFilter.value = [...kinds].includes(current) ? current : "";
  state.sourceKind = els.sourceKindFilter.value;
}

function renderProcedures() {
  const filtered = state.procedures.filter((procedure) => {
    const haystack = `${procedure.name ?? ""} ${procedure.__file}`.toLowerCase();
    return !state.procedureQuery || haystack.includes(state.procedureQuery);
  });

  els.procedureCount.textContent = formatNumber(filtered.length);
  els.procedureList.innerHTML = "";

  if (filtered.length === 0) {
    els.procedureList.innerHTML = `<div class="empty-state detail-content">Eslesen procedure yok.</div>`;
    return;
  }

  for (const procedure of filtered) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `procedure-item${procedure.__id === state.selectedProcedure?.__id ? " active" : ""}`;
    button.innerHTML = `
      <span class="procedure-name">${escapeHtml(procedure.name ?? "(adsiz procedure)")}</span>
      <span class="procedure-meta">${formatNumber((procedure.outputColumns ?? []).length)} kolon · ${escapeHtml(shortFileName(procedure.__file))}</span>
    `;
    button.addEventListener("click", () => {
      state.selectedProcedure = procedure;
      state.selectedColumn = procedure.outputColumns?.[0] ?? null;
      renderSelectedProcedure();
      renderProcedures();
      renderColumns();
      renderDetail();
    });
    els.procedureList.append(button);
  }
}

function renderSelectedProcedure() {
  if (!state.selectedProcedure) {
    els.selectedProcedureTitle.textContent = "Procedure secin";
    els.selectedProcedureFile.textContent = "";
    return;
  }

  els.selectedProcedureTitle.textContent = state.selectedProcedure.name ?? "(adsiz procedure)";
  els.selectedProcedureFile.textContent = state.selectedProcedure.__file;
}

function renderColumns() {
  els.columnTableBody.innerHTML = "";

  const columns = getFilteredColumns();
  if (!state.selectedProcedure) {
    els.columnTableBody.innerHTML = `<tr><td colspan="5">Procedure secin.</td></tr>`;
    return;
  }

  if (columns.length === 0) {
    els.columnTableBody.innerHTML = `<tr><td colspan="5">Eslesen kolon yok.</td></tr>`;
    return;
  }

  if (!columns.includes(state.selectedColumn)) {
    state.selectedColumn = columns[0];
  }

  for (const column of columns) {
    const row = document.createElement("tr");
    row.className = column === state.selectedColumn ? "active" : "";
    row.innerHTML = `
      <td><strong>${escapeHtml(column.name ?? "(adsiz kolon)")}</strong></td>
      <td><div class="formula">${escapeHtml(firstFormula(column))}</div></td>
      <td>${renderSourceBadges(column)}</td>
      <td class="number">${formatNumber((column.operations ?? []).length)}</td>
      <td class="number">${formatNumber((column.branches ?? []).length)}</td>
    `;
    row.addEventListener("click", () => {
      state.selectedColumn = column;
      renderColumns();
      renderDetail();
    });
    els.columnTableBody.append(row);
  }
}

function getFilteredColumns() {
  const columns = state.selectedProcedure?.outputColumns ?? [];
  return columns.filter((column) => {
    if (state.sourceKind && !columnHasKind(column, state.sourceKind)) {
      return false;
    }

    if (!state.columnQuery) {
      return true;
    }

    const haystack = [
      column.name,
      ...(column.formulas ?? []),
      ...(column.operations ?? []),
      ...getAllColumnSources(column).flatMap(sourceToSearchText),
    ]
      .join(" ")
      .toLowerCase();

    return haystack.includes(state.columnQuery);
  });
}

function renderSourceBadges(column) {
  const sourceCounts = new Map();
  for (const source of getAllColumnSources(column)) {
    collectSourceKindCounts(source, sourceCounts);
  }

  if (sourceCounts.size === 0) {
    return `<span class="badge">Yok</span>`;
  }

  return `<div class="badge-row">${[...sourceCounts.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([kind, count]) => `<span class="badge ${kindClass(kind)}">${escapeHtml(kind)} ${formatNumber(count)}</span>`)
    .join("")}</div>`;
}

function renderDetail() {
  const column = state.selectedColumn;
  if (!column) {
    els.detailContent.className = "detail-content empty-state";
    els.detailContent.textContent = "Bir kolon secildiginde formul, kaynak zinciri ve branch detaylari burada gorunur.";
    return;
  }

  els.detailContent.className = "detail-content";
  const sources = getAllColumnSources(column);
  els.detailContent.innerHTML = `
    <section class="detail-section">
      <h3>Kolon</h3>
      <div class="detail-card"><strong>${escapeHtml(column.name ?? "(adsiz kolon)")}</strong></div>
    </section>
    <section class="detail-section">
      <h3>Formuller</h3>
      ${(column.formulas ?? []).map((formula) => `<div class="detail-card formula">${escapeHtml(formula)}</div>`).join("") || `<div class="detail-card muted">Formul yok.</div>`}
    </section>
    <section class="detail-section">
      <h3>Operations</h3>
      <div class="badge-row">${(column.operations ?? []).map((op) => `<span class="badge">${escapeHtml(op)}</span>`).join("") || `<span class="badge">Yok</span>`}</div>
    </section>
    <section class="detail-section">
      <h3>Sources</h3>
      ${sources.map((source) => renderSourceTree(source)).join("") || `<div class="detail-card muted">Source yok.</div>`}
    </section>
    <section class="detail-section">
      <h3>Branches</h3>
      ${(column.branches ?? []).map(renderBranch).join("") || `<div class="detail-card muted">Branch yok.</div>`}
    </section>
  `;
}

function renderBranch(branch) {
  return `
    <div class="detail-card">
      <div><strong>${escapeHtml(branch.branch ?? "branch")}</strong>${branch.line ? ` · line ${escapeHtml(String(branch.line))}` : ""}</div>
      <div class="formula">${escapeHtml(branch.formula ?? "")}</div>
      <div class="badge-row">${(branch.operations ?? []).map((op) => `<span class="badge">${escapeHtml(op)}</span>`).join("")}</div>
      ${(branch.sources ?? []).map((source) => renderSourceTree(source)).join("")}
    </div>
  `;
}

function renderSourceTree(source) {
  const kind = source.sourceKind ?? "Unknown";
  const objectName = source.objectName || [source.server, source.database, source.schema, source.table].filter(Boolean).join(".") || "(unknown object)";
  const column = source.column ? `.${source.column}` : "";
  const alias = source.alias ? `alias ${source.alias}` : "";
  const unresolved = source.unresolved ? `<span class="badge">unresolved</span>` : "";
  const formula = source.formula ? `<div class="formula">${escapeHtml(source.formula)}</div>` : "";
  const children = (source.derivedSources ?? []).map((child) => renderSourceTree(child)).join("");

  return `
    <div class="source-node">
      <div class="source-title">
        <span class="badge ${kindClass(kind)}">${escapeHtml(kind)}</span>
        <span>${escapeHtml(objectName + column)}</span>
        ${unresolved}
      </div>
      <div class="source-sub">${escapeHtml(alias)}</div>
      ${formula}
      ${children}
    </div>
  `;
}

function renderAnalytics() {
  const kindCounts = new Map();
  const objectCounts = new Map();

  for (const procedure of state.procedures) {
    for (const column of procedure.outputColumns ?? []) {
      for (const source of getAllColumnSources(column)) {
        collectSourceKindCounts(source, kindCounts);
        collectObjectCounts(source, objectCounts);
      }
    }
  }

  renderBars(kindCounts);
  renderTopObjects(objectCounts);
}

function renderBars(counts) {
  const rows = [...counts.entries()].sort((a, b) => b[1] - a[1]);
  const max = Math.max(1, ...rows.map(([, count]) => count));
  els.kindChart.innerHTML = rows
    .map(([kind, count]) => {
      const width = Math.max(4, Math.round((count / max) * 100));
      return `
        <div class="bar-row">
          <span><span class="badge ${kindClass(kind)}">${escapeHtml(kind)}</span></span>
          <span class="bar-track"><span class="bar-fill" style="width: ${width}%"></span></span>
          <span class="number">${formatNumber(count)}</span>
        </div>
      `;
    })
    .join("") || `<div class="empty-state">Source turu yok.</div>`;
}

function renderTopObjects(counts) {
  const rows = [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 15);
  els.topObjects.innerHTML = rows
    .map(([objectName, count]) => `
      <div class="object-row">
        <span class="object-name" title="${escapeHtml(objectName)}">${escapeHtml(objectName)}</span>
        <span class="number">${formatNumber(count)}</span>
      </div>
    `)
    .join("") || `<div class="empty-state">Object yok.</div>`;
}

function switchTab(tab) {
  state.activeTab = tab;
  const raw = tab === "raw";
  els.tableTab.classList.toggle("active", !raw);
  els.rawTab.classList.toggle("active", raw);
  els.tableView.classList.toggle("hidden", raw);
  els.rawView.classList.toggle("hidden", !raw);
}

function getAllColumnSources(column) {
  return [...(column.sources ?? []), ...(column.branches ?? []).flatMap((branch) => branch.sources ?? [])];
}

function countSourceTree(source) {
  return 1 + (source.derivedSources ?? []).reduce((sum, child) => sum + countSourceTree(child), 0);
}

function collectKinds(source, kinds) {
  kinds.add(source.sourceKind ?? "Unknown");
  for (const child of source.derivedSources ?? []) {
    collectKinds(child, kinds);
  }
}

function collectSourceKindCounts(source, counts) {
  const kind = source.sourceKind ?? "Unknown";
  counts.set(kind, (counts.get(kind) ?? 0) + 1);
  for (const child of source.derivedSources ?? []) {
    collectSourceKindCounts(child, counts);
  }
}

function collectObjectCounts(source, counts) {
  const objectName = source.objectName || [source.server, source.database, source.schema, source.table].filter(Boolean).join(".") || "(unknown)";
  counts.set(objectName, (counts.get(objectName) ?? 0) + 1);
  for (const child of source.derivedSources ?? []) {
    collectObjectCounts(child, counts);
  }
}

function columnHasKind(column, kind) {
  return getAllColumnSources(column).some((source) => sourceTreeHasKind(source, kind));
}

function sourceTreeHasKind(source, kind) {
  return (source.sourceKind ?? "Unknown") === kind || (source.derivedSources ?? []).some((child) => sourceTreeHasKind(child, kind));
}

function sourceToSearchText(source) {
  return [
    source.alias,
    source.objectName,
    source.server,
    source.database,
    source.schema,
    source.table,
    source.sourceKind,
    source.column,
    source.formula,
    ...(source.derivedSources ?? []).flatMap(sourceToSearchText),
  ].filter(Boolean);
}

function firstFormula(column) {
  return column.formulas?.[0] ?? "";
}

function shortFileName(filePath) {
  return filePath.split("/").pop() ?? filePath;
}

function kindClass(kind) {
  return String(kind ?? "").toLowerCase();
}

function formatNumber(value) {
  return new Intl.NumberFormat("tr-TR").format(value ?? 0);
}

function setError(message) {
  els.errorPanel.textContent = message;
  els.errorPanel.classList.toggle("hidden", !message);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
