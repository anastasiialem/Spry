import { meetingStatusSchema, type MeetingCreate } from "@/lib/api";

export type FieldErrors = Partial<Record<keyof MeetingCreate | "form", string>>;

/** "2026-10-05T12:00" in the browser's zone -> "2026-10-05T09:00:00.000Z". */
const toUtc = (local: string) => new Date(local).toISOString();

/** "2026-10-05T09:00:00Z" -> "2026-10-05T12:00" for a datetime-local input (local zone). */
export function toLocalInput(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(
    d.getHours(),
  )}:${pad(d.getMinutes())}`;
}

/** Client-side mirror of the API rules (PROJECT.md §4); the server re-checks everything. */
export function validateMeeting(form: FormData): {
  payload?: MeetingCreate;
  errors: FieldErrors;
} {
  const title = String(form.get("title") ?? "").trim();
  const start = String(form.get("starts_at") ?? "");
  const end = String(form.get("ends_at") ?? "");
  const count = Number(form.get("attendee_count"));
  const status = meetingStatusSchema
    .catch("not_started")
    .parse(form.get("status"));
  const errors: FieldErrors = {};

  if (!title) errors.title = "Title is required";
  else if (title.length > 200) errors.title = "At most 200 characters";
  if (!start) errors.starts_at = "Start is required";
  if (!end) errors.ends_at = "End is required";
  else if (start && new Date(end) <= new Date(start))
    errors.ends_at = "End must be after start";
  if (!Number.isInteger(count) || count < 1 || count > 1000)
    errors.attendee_count = "Between 1 and 1000";

  if (Object.keys(errors).length > 0) return { errors };
  return {
    errors,
    payload: {
      title,
      starts_at: toUtc(start),
      ends_at: toUtc(end),
      attendee_count: count,
      status,
    },
  };
}
