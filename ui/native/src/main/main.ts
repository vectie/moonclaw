import { setupMoonclawProcess } from "@moonclaw/core/lib/node/moonclaw-setup.js";
import { getApi, shutdown } from "@moonclaw/core/lib/node/moonclaw-util.js";
import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  OpenDialogReturnValue,
  shell,
} from "electron";
import started from "electron-squirrel-startup";
import path from "path";
import { getResolvedShellEnv } from "./shellEnv";

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (started) {
  app.quit();
}

let mainWindow: BrowserWindow | null;

function moonclawWorkspaceRoot(): string {
  return (
    process.env["MOONSUITE_ROOT"] ??
    process.env["MOONCLAW_WORKSPACE_ROOT"] ??
    process.cwd()
  );
}

function createWindow() {
  // Create the browser window.
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    webPreferences: {
      preload: path.join(__dirname, "../preload/preload.js"),
    },
  });

  // and load the index.html of the app.
  if (process.env.moonclaw_DEV) {
    mainWindow.loadURL(`http://localhost:5173`);
    // Open the DevTools.
    mainWindow.webContents.openDevTools();
  } else {
    mainWindow.loadFile(path.join(__dirname, `../renderer/index.html`));
  }
}

async function setupmoonclaw() {
  const shellEnv = await getResolvedShellEnv();
  const moonclawPath = process.env.moonclaw_DEV
    ? path.join(
        __dirname,
        "../../../../target/native/release/build/cmd/main/main.exe",
      )
    : path.join(__dirname, "../bin/moonclaw");
  return await setupMoonclawProcess(
    moonclawPath,
    moonclawWorkspaceRoot(),
    shellEnv,
  );
}

async function shutdownmoonclawDaemon() {
  await shutdown(moonclawWorkspaceRoot());
}

const onReady = async () => {
  // TODO: dont await the promise, we will show a loading screen in the renderer
  const [_, error] = await setupmoonclaw();
  if (error) {
    dialog.showErrorBox("Error", error.message);
    app.exit(1);
    return;
  }
  createWindow();
};

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.
app.on("ready", onReady);

// Quit when all windows are closed, except on macOS. There, it's common
// for applications and their menu bar to stay active until the user quits
// explicitly with Cmd + Q.
app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  // On OS X it's common to re-create a window in the app when the
  // dock icon is clicked and there are no other windows open.
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});

// In this file you can include the rest of your app's specific main process
// code. You can also put them in separate files and import them here.
ipcMain.handle("select-directory", async (): Promise<OpenDialogReturnValue> => {
  if (!mainWindow) return { canceled: true, filePaths: [] };
  return await dialog.showOpenDialog(mainWindow, {
    properties: ["openDirectory", "createDirectory", "promptToCreate"],
  });
});

ipcMain.handle("get-url", async () => {
  const [url, error] = await getApi(moonclawWorkspaceRoot());
  if (error) {
    dialog.showErrorBox("Error", error.message);
    app.exit(1);
    return;
  }
  return url;
});

ipcMain.handle("moonclaw-ready", async () => {
  await setupmoonclaw();
});

ipcMain.handle("reload-app", async () => {
  app.relaunch();
  await shutdownmoonclawDaemon();
  app.exit();
});

ipcMain.handle(
  "open-path-in-file-explorer",
  async (_event, filePath: string) => {
    if (!mainWindow) return;
    await shell.openPath(filePath);
  },
);
