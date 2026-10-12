const { app, BrowserWindow, dialog, shell } = require('electron');
const { createServer } = require('node:http');
const { readFile, stat } = require('node:fs/promises');
const path = require('node:path');

const singleInstance = app.requestSingleInstanceLock();
if (!singleInstance) app.quit();

if (singleInstance && process.env.PORTABLE_EXECUTABLE_DIR) {
  const portableData = path.join(process.env.PORTABLE_EXECUTABLE_DIR, 'Daily Red Data');
  try {
    require('node:fs').mkdirSync(portableData, { recursive: true });
    app.setPath('userData', portableData);
  } catch (error) {
    console.warn('Could not create portable data folder; using the Windows profile instead.', error);
  }
}

const mimeTypes = {
  '.css': 'text/css; charset=utf-8',
  '.gba': 'application/octet-stream',
  '.gz': 'application/octet-stream',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm',
};

const webRoot = app.isPackaged
  ? path.join(process.resourcesPath, 'web')
  : path.resolve(__dirname, '..', 'web');
let server;
let mainWindow;
let serverOrigin;

function makeServer() {
  return createServer(async (request, response) => {
    try {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        response.writeHead(405, { Allow: 'GET, HEAD' });
        response.end();
        return;
      }

      const url = new URL(request.url, serverOrigin);
      const decodedPath = decodeURIComponent(url.pathname);
      const filePath = path.resolve(webRoot, `.${decodedPath}`);
      if (filePath !== webRoot && !filePath.startsWith(`${webRoot}${path.sep}`)) {
        response.writeHead(403);
        response.end('Forbidden');
        return;
      }

      let target = filePath;
      if ((await stat(target)).isDirectory()) target = path.join(target, 'index.html');
      const body = await readFile(target);
      response.writeHead(200, {
        'Content-Type': mimeTypes[path.extname(target).toLowerCase()] || 'application/octet-stream',
        'Cache-Control': 'no-cache',
        'X-Content-Type-Options': 'nosniff',
      });
      response.end(request.method === 'HEAD' ? undefined : body);
    } catch (error) {
      response.writeHead(error.code === 'EACCES' ? 403 : 404, {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      response.end(error.code === 'EACCES' ? 'Forbidden' : 'Not found');
    }
  });
}

async function createWindow() {
  mainWindow = new BrowserWindow({
    title: 'Daily Red',
    width: 1120,
    height: 820,
    minWidth: 780,
    minHeight: 640,
    autoHideMenuBar: true,
    backgroundColor: '#111827',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https://')) shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (new URL(url).origin !== serverOrigin) event.preventDefault();
  });
  await mainWindow.loadURL(serverOrigin);
  mainWindow.on('closed', () => { mainWindow = null; });
}

if (singleInstance) {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(async () => {
    try {
      server = makeServer();
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', resolve);
      });
      serverOrigin = `http://127.0.0.1:${server.address().port}`;
      await createWindow();
    } catch (error) {
      dialog.showErrorBox('Daily Red could not start', error.message);
      app.quit();
    }
  });

  app.on('before-quit', () => server?.close());
  app.on('window-all-closed', () => app.quit());
}
