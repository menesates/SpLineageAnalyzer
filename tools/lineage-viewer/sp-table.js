const state = {
  data: [],
  procedures: [],
  selectedProcedure: null,
  procedureQuery: "",
  lineageQuery: "",
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
  columnCount: document.querySelector("#columnCount"),
  lineageSearch: document.querySelector("#lineageSearch"),
  lineageTableBody: document.querySelector("#lineageTableBody"),
};

els.reloadButton.addEventListener("click", () => loadData());
els.procedureSearch.addEventListener("input", (event) => {
  state.procedureQuery = event.target.value.trim().toLowerCase();
  renderProcedures();
});
els.lineageSearch.addEventListener("input", (event) => {
  state.lineageQuery = event.target.value.trim().toLowerCase();
  renderLineageTable();
});

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

    const loadedAt = new Date().toLocaleTimeString("tr-TR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    els.loadStatus.textContent = `${loadedAt} yuklendi`;
    renderAll();
  } catch (error) {
    state.data = [];
    state.procedures = [];
    state.selectedProcedure = null;
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
    }));
  });
}

function renderAll() {
  renderProcedures();
  renderSelectedProcedure();
  renderLineageTable();
}

function renderProcedures() {
  const filtered = state.procedures.filter((procedure) => {
    const haystack = `${procedure.name ?? ""} ${procedure.__file}`.toLowerCase();
    return !state.procedureQuery || haystack.includes(state.procedureQuery);
  });

  els.procedureCount.textContent = formatNumber(filtered.length);
  els.procedureList.innerHTML = "";

  if (filtered.length === 0) {
    els.procedureList.innerHTML = `<div class="empty-state detail-content">Eslesen SP yok.</div>`;
    return;
  }

  for (const procedure of filtered) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `procedure-item${procedure.__id === state.selectedProcedure?.__id ? " active" : ""}`;
    button.innerHTML = `
      <span class="procedure-name">${escapeHtml(procedure.name ?? "(adsiz procedure)")}</span>
      <span class="procedure-meta">${formatNumber((procedure.outputColumns ?? []).length)} output kolon · ${escapeHtml(shortFileName(procedure.__file))}</span>
    `;
    button.addEventListener("click", () => {
      state.selectedProcedure = procedure;
      renderProcedures();
      renderSelectedProcedure();
      renderLineageTable();
    });
    els.procedureList.append(button);
  }
}

function renderSelectedProcedure() {
  if (!state.selectedProcedure) {
    els.selectedProcedureTitle.textContent = "Procedure secin";
    els.selectedProcedureFile.textContent = "";
    els.columnCount.textContent = "0 kolon";
    return;
  }

  const columnCount = state.selectedProcedure.outputColumns?.length ?? 0;
  els.selectedProcedureTitle.textContent = state.selectedProcedure.name ?? "(adsiz procedure)";
  els.selectedProcedureFile.textContent = state.selectedProcedure.__file;
  els.columnCount.textContent = `${formatNumber(columnCount)} kolon`;
}

function renderLineageTable() {
  els.lineageTableBody.innerHTML = "";

  if (!state.selectedProcedure) {
    els.lineageTableBody.innerHTML = `<tr><td colspan="5">Procedure secin.</td></tr>`;
    return;
  }

  const rows = buildRows(state.selectedProcedure.outputColumns ?? []).filter((row) => {
    if (!state.lineageQuery) {
      return true;
    }

    return row.searchText.includes(state.lineageQuery);
  });

  if (rows.length === 0) {
    els.lineageTableBody.innerHTML = `<tr><td colspan="5">Eslesen output kolon yok.</td></tr>`;
    return;
  }

  for (const row of rows) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><strong>${escapeHtml(row.outputColumn)}</strong></td>
      <td><div class="formula">${renderFormulaList(row.formulas)}</div></td>
      <td>${renderChipList(row.tables, "table-chip")}</td>
      <td>${renderColumnList(row.sourceColumns)}</td>
      <td>${renderLineList(row.lines)}</td>
    `;
    els.lineageTableBody.append(tr);
  }
}

function buildRows(columns) {
  return columns.map((column) => {
    const sourceAccumulator = {
      tables: new Map(),
      columns: new Map(),
    };

    for (const source of getAllColumnSources(column)) {
      collectSourceInfo(source, sourceAccumulator);
    }

    const formulas = uniqueStrings(column.formulas ?? []);
    const lines = uniqueStrings((column.branches ?? []).map((branch) => branch.line).filter((line) => line !== null && line !== undefined).map(String));
    const tables = [...sourceAccumulator.tables.values()].sort((a, b) => a.label.localeCompare(b.label));
    const sourceColumns = [...sourceAccumulator.columns.values()].sort((a, b) => a.label.localeCompare(b.label));

    return {
      outputColumn: column.name ?? "(adsiz kolon)",
      formulas,
      tables,
      sourceColumns,
      lines,
      searchText: [
        column.name,
        ...formulas,
        ...tables.map((table) => table.label),
        ...sourceColumns.map((sourceColumn) => sourceColumn.label),
        ...lines,
      ].join(" ").toLowerCase(),
    };
  });
}

function collectSourceInfo(source, accumulator) {
  const objectName = normalizeObjectName(source);
  const kind = source.sourceKind ?? "Unknown";
  const tableKey = `${kind}:${objectName}`;

  if (objectName && !accumulator.tables.has(tableKey)) {
    accumulator.tables.set(tableKey, {
      label: objectName,
      kind,
    });
  }

  if (source.column) {
    const columnLabel = objectName ? `${objectName}.${source.column}` : source.column;
    const columnKey = `${kind}:${columnLabel}`;
    if (!accumulator.columns.has(columnKey)) {
      accumulator.columns.set(columnKey, {
        label: columnLabel,
        kind,
      });
    }
  }

  for (const child of source.derivedSources ?? []) {
    collectSourceInfo(child, accumulator);
  }
}

function getAllColumnSources(column) {
  return [...(column.sources ?? []), ...(column.branches ?? []).flatMap((branch) => branch.sources ?? [])];
}

function normalizeObjectName(source) {
  return source.objectName || [source.server, source.database, source.schema, source.table].filter(Boolean).join(".") || source.table || "";
}

function renderFormulaList(formulas) {
  if (formulas.length === 0) {
    return `<span class="muted">Formul yok</span>`;
  }

  return formulas.map((formula) => `<div>${escapeHtml(formula)}</div>`).join("");
}

function renderChipList(items, extraClass = "") {
  if (items.length === 0) {
    return `<span class="muted">Kaynak yok</span>`;
  }

  return `<div class="lineage-chip-list">${items.map((item) => `<span class="lineage-chip ${kindClass(item.kind)} ${extraClass}">${escapeHtml(item.label)}</span>`).join("")}</div>`;
}

function renderColumnList(items) {
  if (items.length === 0) {
    return `<span class="muted">Kolon yok</span>`;
  }

  return `<div class="source-column-list">${items.map((item) => `<code class="source-column">${escapeHtml(item.label)}</code>`).join("")}</div>`;
}

function renderLineList(lines) {
  if (lines.length === 0) {
    return `<span class="muted">-</span>`;
  }

  return `<div class="line-list">${lines.map((line) => `<span class="line-number">${escapeHtml(line)}</span>`).join("")}</div>`;
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => value !== null && value !== undefined && String(value).trim() !== "").map(String))];
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
