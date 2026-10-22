import { z } from "zod";

import { getAccessToken } from "@/lib/auth";

/** Compiled in by Vite at build time (dev server: read from the environment). */
const API_URL = (
  import.meta.env.VITE_API_URL ?? "http://localhost:8000"
).replace(/\/$/, "");

/** The agenda parser's own function URL (make deploy-ai). Empty: no "Paste an agenda". */
const PARSER_URL = (
  (import.meta.env.VITE_PARSER_URL as string | undefined) ?? ""
).replace(/\/$/, "");
export const parserEnabled = PARSER_URL !== "";
/** Same limit as the parser (app/ai/agenda.py), checked before sending. */
export const MAX_PASTE_CHARS = 10_000;

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

/* --- agendas (PROJECT.md section 11) --- */

const agendaItemSchema = z.object({
  topic: z.string(),
  owner: z.string().nullable(),
  minutes: z.number().int().nullable(),
});
const actionItemSchema = z.object({
  task: z.string(),
  owner: z.string().nullable(),
  due: z.iso.date().nullable(),
});
export type AgendaItem = z.infer<typeof agendaItemSchema>;
export type ActionItem = z.infer<typeof actionItemSchema>;

export const agendaSchema = z.object({
  meeting_id: z.number().int(),
  items: z.array(agendaItemSchema),
  action_items: z.array(actionItemSchema),
  ai_model: z.string().nullable(),
  ai_prompt_version: z.string().nullable(),
  updated_at: z.iso.datetime(),
});
export type Agenda = z.infer<typeof agendaSchema>;

/** What the parser suggests. Not trusted: parsed here as well as on the server. */
export const parsedAgendaSchema = z.object({
  title: z.string().nullable(),
  starts_at: z.string().nullable(),
  duration_minutes: z.number().int().nullable(),
  items: z.array(agendaItemSchema),
  action_items: z.array(actionItemSchema),
  language: z.string(),
});
export type ParsedAgenda = z.infer<typeof parsedAgendaSchema>;

const parseResultSchema = z.object({
  agenda: parsedAgendaSchema,
  model: z.string(),
  prompt_version: z.string(),
});
export type ParseResult = z.infer<typeof parseResultSchema>;

export type AgendaWrite = {
  items: AgendaItem[];
  action_items: ActionItem[];
  /** The parser's untouched answer, stored next to what the user saved. */
  ai_suggestion: ParseResult | null;
};

const PARSE_ERRORS: Record<number, string> = {
  400: "The parser could not read that request.",
  401: "Your session has expired - please sign in again.",
  413: `The text is longer than ${MAX_PASTE_CHARS.toLocaleString("en")} characters.`,
  422: "No agenda found in that text. Edit it, or type the agenda by hand.",
  429: "The AI service is busy right now. Try again in a minute, or type the agenda by hand.",
  503: "The AI service is unavailable. Type the agenda by hand - everything else works.",
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

/** POST the pasted text to the parser. The user's date and zone resolve "Monday". */
async function parseAgenda(
  text: string,
  signal: AbortSignal,
): Promise<ParseResult> {
  const now = new Date();
  const today = [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, "0"),
    String(now.getDate()).padStart(2, "0"),
  ].join("-");
  let response: Response;
  try {
    response = await fetch(PARSER_URL, {
      method: "POST",
      signal,
      headers: { "Content-Type": "application/json", ...authHeaders() },
      body: JSON.stringify({
        text,
        today,
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
    });
  } catch (error) {
    if (signal.aborted) throw error; // Cancel: not an error to show
    throw new ApiError(
      0,
      "Could not reach the parser - check your connection.",
    );
  }
  if (!response.ok) {
    const message =
      PARSE_ERRORS[response.status] ??
      `The parser failed (${response.status}).`;
    throw new ApiError(response.status, message);
  }
  return parseResultSchema.parse(await response.json());
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
  /** The agenda and the files go with it. */
  deleteMeeting: (id: number) =>
    request(`/api/meetings/${id}`, z.undefined(), { method: "DELETE" }),
  updateMeetingStatus: (id: number, status: MeetingStatus) =>
    request(`/api/meetings/${id}`, meetingSchema, {
      method: "PATCH",
      body: JSON.stringify({ status }),
    }),

  /** null when the meeting has no agenda yet (404). */
  getAgenda: (meetingId: number) =>
    request(`/api/meetings/${meetingId}/agenda`, agendaSchema).catch(
      (error: unknown) => {
        if (error instanceof ApiError && error.status === 404) return null;
        throw error;
      },
    ),
  saveAgenda: (meetingId: number, agenda: AgendaWrite) =>
    request(`/api/meetings/${meetingId}/agenda`, agendaSchema, {
      method: "PUT",
      body: JSON.stringify(agenda),
    }),
  /** Only suggests. Saving always goes through saveAgenda, never the parser. */
  parseAgenda,

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
