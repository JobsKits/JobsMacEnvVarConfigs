function chromeDownloadsSearch(query) {
  return new Promise((resolve, reject) => {
    try {
      chrome.downloads.search(query, (items) => {
        const err = chrome.runtime.lastError;
        if (err) reject(new Error(err.message));
        else resolve(items || []);
      });
    } catch (error) {
      reject(error);
    }
  });
}

function chromeDownloadsErase(query) {
  return new Promise((resolve, reject) => {
    try {
      chrome.downloads.erase(query, (ids) => {
        const err = chrome.runtime.lastError;
        if (err) reject(new Error(err.message));
        else resolve(ids || []);
      });
    } catch (error) {
      reject(error);
    }
  });
}

async function clearDownloads() {
  const before = await chromeDownloadsSearch({});
  const erasedIds = await chromeDownloadsErase({});
  const after = await chromeDownloadsSearch({});

  return {
    ok: true,
    before: before.length,
    erased: erasedIds.length,
    after: after.length,
    erasedIds,
    time: new Date().toISOString()
  };
}

chrome.action.onClicked.addListener(async () => {
  await clearDownloads();
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command === 'clear-download-history') {
    await clearDownloads();
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== 'JOBS_CLR_CLEAR_DOWNLOADS') {
    return false;
  }

  clearDownloads()
    .then((result) => sendResponse(result))
    .catch((error) => sendResponse({ ok: false, error: String(error && error.message ? error.message : error) }));

  return true;
});
