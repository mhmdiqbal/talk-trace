/** Pure text builders for the popup's one message line. */

export function formatSeconds(total: number): string {
  const whole = Math.floor(total);
  const minutes = Math.floor(whole / 60);
  const seconds = whole % 60;
  return `${String(minutes)}:${String(seconds).padStart(2, "0")}`;
}

export function helperExitMessage(
  giveUp: boolean,
  wasRecording: boolean,
  code: number | null,
  signal: string | null,
): string | null {
  if (giveUp) return "The audio helper keeps crashing. Quit TalkTrace and check Console for details.";
  if (!wasRecording) return null;
  return `The audio helper stopped during a recording (code ${String(code ?? signal)}). The file may be short.`;
}
