import path from "node:path";
import { Notification, shell } from "electron";

// The popup is shut most of the time, so the message line alone is not enough
// to tell anyone a transcript landed.
export function transcriptReady(srtPath: string): void {
  if (!Notification.isSupported()) return;
  const notification = new Notification({
    title: "Transcript ready",
    body: path.basename(srtPath),
  });
  notification.on("click", () => { shell.showItemInFolder(srtPath); });
  notification.show();
}
