import { Menu, type BrowserWindow } from "electron";
import type { MicDevice } from "./protocol";

export type MicMenuArgs = {
  window: BrowserWindow;
  mics: MicDevice[];
  selectedMicID: string | null;
  micEnabled: boolean;
  onPick: (enabled: boolean, micID: string | null) => void;
  onOpenChange: (open: boolean) => void;
};

// A native Menu, not a <select>. The popup's blur handler returns early while
// this is open, so the popup cannot hide underneath it.
export function openMicMenu(args: MicMenuArgs): void {
  const menu = Menu.buildFromTemplate([
    {
      label: "Off (Mac audio only)",
      type: "checkbox",
      checked: !args.micEnabled,
      click: () => { args.onPick(false, args.selectedMicID); },
    },
    { type: "separator" },
    {
      label: "System default",
      type: "checkbox",
      checked: args.micEnabled && args.selectedMicID === null,
      click: () => { args.onPick(true, null); },
    },
    ...args.mics.map((mic) => ({
      label: mic.name,
      type: "checkbox" as const,
      checked: args.micEnabled && mic.id === args.selectedMicID,
      click: () => { args.onPick(true, mic.id); },
    })),
  ]);

  args.onOpenChange(true);
  menu.popup({
    window: args.window,
    callback: () => { args.onOpenChange(false); },
  });
}
