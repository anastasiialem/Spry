import { z } from "zod";

/** Compiled in by Vite at build time (dev server: read from the environment). */
const API_URL = (
  import.meta.env.VITE_API_URL ?? "http://localhost:8000"
).replace(/\/$/, "");

/* --- schemas mirroring PROJECT.md section 4 --- */

export const meetingSchema = z.object({
  id: z.number().int(),
  title: z.string(),
  starts_at: z.iso.datetime(),
  ends_at: z.iso.datetime(),
  attendee_count: z.number().int(),
});

export const meetingListSchema = z.array(meetingSchema);

export type Meeting = z.infer<typeof meetingSchema>;

export type MeetingCreate = {
  title: string;
  starts_at: string; // ISO 8601, UTC
  ends_at: string;
  attendee_count: number;
};

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

async function request<T>(
  path: string,
  schema: z.ZodType<T>,
  init?: RequestInit,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${API_URL}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json", ...init?.headers },
    });
  } catch {
    throw new ApiError(0, "Could not reach the API");
  }

  if (!response.ok) {
    const body = await response.json().catch(() => null);
    const detail = body?.detail;
    const message =
      typeof detail === "string"
        ? detail
        : Array.isArray(detail)
          ? detail.map((d: { msg?: string }) => d.msg).join("; ")
          : `Request failed (${response.status})`;
    throw new ApiError(response.status, message);
  }
  return schema.parse(await response.json());
}

/** The only place in the frontend that talks to the backend. */
export const api = {
  listMeetings: () => request("/api/meetings", meetingListSchema),
  createMeeting: (payload: MeetingCreate) =>
    request("/api/meetings", meetingSchema, {
      method: "POST",
      body: JSON.stringify(payload),
    }),
};
