import type { MeetingStatus } from "@/lib/api";

/** Labels and colour classes for each status, shared by the pill, the form and the schedule. */
export const STATUS: Record<
  MeetingStatus,
  { label: string; pill: string; dot: string }
> = {
  not_started: {
    label: "Not started",
    pill: "bg-status-todo-bg text-status-todo-fg",
    dot: "bg-status-todo-dot",
  },
  in_progress: {
    label: "In progress",
    pill: "bg-status-progress-bg text-status-progress-fg",
    dot: "bg-status-progress-dot",
  },
  done: {
    label: "Done",
    pill: "bg-status-done-bg text-status-done-fg",
    dot: "bg-status-done-dot",
  },
};
