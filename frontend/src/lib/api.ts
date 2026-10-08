import { z } from "zod";

import { getAccessToken } from "@/lib/auth";

/** Compiled in by Vite at build time (dev server: read from the environment). */
const API_URL = (
  import.meta.env.VITE_API_URL ?? "http://localhost:8000"
).replace(/\/$/, "");

/* --- schemas mirroring PROJECT.md section 4 --- */

export const meetingStatuses = ["not_started", "in_progress", "done"] as const;
export const meetingStatusSchema = z.enum(meetingStatuses);
export type MeetingStatus = z.infer<typeof meetingStatusSchema>;

export const meetingSchema = z.object({
  id: z.number().int(),
  title: z.string(),
  starts_at: z.iso.datetime(),
  ends_at: z.iso.datetime(),
  attendee_count: z.number().int(),
  status: meetingStatusSchema,
  attachment_count: z.number().int(),
});

export const meetingListSchema = z.array(meetingSchema);

export type Meeting = z.infer<typeof meetingSchema>;

export const attachmentSchema = z.object({
  id: z.number().int(),
  meeting_id: z.number().int(),
  filename: z.string(),
  content_type: z.string(),
  size: z.number().int(),
  created_at: z.iso.datetime(),
});
export type Attachment = z.infer<typeof attachmentSchema>;

/** Same limit as the backend (PROJECT.md §4). */
export const MAX_ATTACHMENT_BYTES = 4 * 1024 * 1024;

export type MeetingCreate = {
  title: string;
  starts_at: string; // ISO 8601, UTC
  ends_at: string;
  attendee_count: number;
  status: MeetingStatus;
};

export type MeetingPatch = Partial<MeetingCreate>;

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

/** Every API call carries the access token; the API answers 401 without it. */
function authHeaders(): Record<string, string> {
  const token = getAccessToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function send(path: string, init?: RequestInit): Promise<Response> {
  let response: Response;
  try {
    response = await fetch(`${API_URL}${path}`, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        ...authHeaders(),
        ...init?.headers,
      },
    });
  } catch {
    throw new ApiError(0, "Could not reach the API");
  }
  if (response.status === 401) {
    throw new ApiError(401, "Your session has expired - please sign in again");
  }
  return response;
}

async function request<T>(
  path: string,
  schema: z.ZodType<T>,
  init?: RequestInit,
): Promise<T> {
  const response = await send(path, init);

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
  if (response.status === 204) return schema.parse(undefined);
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
  updateMeeting: (id: number, patch: MeetingPatch) =>
    request(`/api/meetings/${id}`, meetingSchema, {
      method: "PATCH",
      body: JSON.stringify(patch),
    }),
  updateMeetingStatus: (id: number, status: MeetingStatus) =>
    request(`/api/meetings/${id}`, meetingSchema, {
      method: "PATCH",
      body: JSON.stringify({ status }),
    }),

  listAttachments: (meetingId: number) =>
    request(
      `/api/meetings/${meetingId}/attachments`,
      z.array(attachmentSchema),
    ),
  /** The file is sent as the raw body; its name travels in the query string. */
  uploadAttachment: (meetingId: number, file: File) =>
    request(
      `/api/meetings/${meetingId}/attachments?filename=${encodeURIComponent(file.name)}`,
      attachmentSchema,
      {
        method: "POST",
        body: file,
        headers: { "Content-Type": file.type || "application/octet-stream" },
      },
    ),
  deleteAttachment: (id: number) =>
    request(`/api/attachments/${id}`, z.undefined(), { method: "DELETE" }),
  /** A plain link cannot send the token, so fetch the file and save it. */
  downloadAttachment: async (id: number, filename: string) => {
    const response = await send(`/api/attachments/${id}`);
    if (!response.ok) throw new ApiError(response.status, "Download failed");
    const url = URL.createObjectURL(await response.blob());
    const link = Object.assign(document.createElement("a"), {
      href: url,
      download: filename,
    });
    link.click();
    URL.revokeObjectURL(url);
  },
};
