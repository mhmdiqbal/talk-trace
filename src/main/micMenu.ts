import { Menu, type BrowserWindow } from "electron";
import type { MicDevice } from "./protocol";

export type MicMenuArgs = {
  window: BrowserWindow;
  mics: MicDevice[];
  selectedMicID: string | null;
  onPick: (micID: string | null) => void;
  onOpenChange: (open: boolean) => void;
};

// A native Menu, not a <select>. The popup's blur handler returns early while
// this is open, so the popup cannot hide underneath it.
export function openMicMenu(args: MicMenuArgs): void {
  const menu = Menu.buildFromTemplate([
    {
      label: "System default",
      type: "checkbox",
      checked: args.selectedMicID === null,
      click: () => { args.onPick(null); },
    },
    { type: "separator" },
    ...args.mics.map((mic) => ({
      label: mic.name,
      type: "checkbox" as const,
      checked: mic.id === args.selectedMicID,
      click: () => { args.onPick(mic.id); },
    })),
  ]);

  args.onOpenChange(true);
  menu.popup({
    window: args.window,
    callback: () => { args.onOpenChange(false); },
  });
}
