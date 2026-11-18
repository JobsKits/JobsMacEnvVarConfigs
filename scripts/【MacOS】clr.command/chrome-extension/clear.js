const statusEl = document.getElementById('status');
const detailEl = document.getElementById('detail');

function setResult(status, detail) {
  statusEl.textContent = status;
  detailEl.textContent = detail;
}

chrome.runtime.sendMessage({ type: 'JOBS_CLR_CLEAR_DOWNLOADS' }, (response) => {
  const err = chrome.runtime.lastError;
  if (err) {
    setResult('清理失败', err.message || String(err));
    return;
  }

  if (!response || !response.ok) {
    setResult('清理失败', response && response.error ? response.error : '未知错误');
    return;
  }

  setResult(
    'Chrome 下载历史已清理',
    `清理前 ${response.before} 条，已移除 ${response.erased} 条，清理后 ${response.after} 条。本地真实文件没有被删除。`
  );
});
