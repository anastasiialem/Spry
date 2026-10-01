import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Download, FileText, Paperclip, Trash2, Upload, X } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent } from "react";

import { MeetingFields } from "@/components/meeting-fields";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import {
  MAX_ATTACHMENT_BYTES,
  api,
  type Meeting,
  type MeetingCreate,
  type MeetingPatch,
} from "@/lib/api";
import { validateMeeting, type FieldErrors } from "@/lib/meeting-validation";

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/** Only the fields whose value actually changed, so PATCH stays minimal. */
function diff(meeting: Meeting, next: MeetingCreate): MeetingPatch {
  const patch: MeetingPatch = {};
  if (next.title !== meeting.title) patch.title = next.title;
  if (Date.parse(next.starts_at) !== Date.parse(meeting.starts_at))
    patch.starts_at = next.starts_at;
  if (Date.parse(next.ends_at) !== Date.parse(meeting.ends_at))
    patch.ends_at = next.ends_at;
  if (next.attendee_count !== meeting.attendee_count)
    patch.attendee_count = next.attendee_count;
  if (next.status !== meeting.status) patch.status = next.status;
  return patch;
}

function Files({ meetingId }: { meetingId: number }) {
  const queryClient = useQueryClient();
  const input = useRef<HTMLInputElement>(null);
  const [error, setError] = useState<string | null>(null);
  const key = ["meetings", meetingId, "attachments"];

  const files = useQuery({
    queryKey: key,
    queryFn: () => api.listAttachments(meetingId),
  });
  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: key }),
      queryClient.invalidateQueries({ queryKey: ["meetings"], exact: true }),
    ]);

  const upload = useMutation({
    mutationFn: (file: File) => api.uploadAttachment(meetingId, file),
    onSuccess: refresh,
    onError: (e) => setError(e.message),
  });
  const remove = useMutation({
    mutationFn: api.deleteAttachment,
    onSuccess: refresh,
    onError: (e) => setError(e.message),
  });

  function onPick(fileList: FileList | null) {
    setError(null);
    const file = fileList?.[0];
    if (input.current) input.current.value = "";
    if (!file) return;
    if (file.size === 0) return setError("That file is empty.");
    if (file.size > MAX_ATTACHMENT_BYTES)
      return setError(`${file.name} is larger than 4 MB.`);
    upload.mutate(file);
  }

  return (
    <section aria-labelledby="files-heading" className="grid gap-3">
      <div className="flex items-center justify-between">
        <h3
          id="files-heading"
          className="inline-flex items-center gap-1.5 text-sm font-semibold"
        >
          <Paperclip className="size-4" />
          Files
        </h3>
        <input
          ref={input}
          type="file"
          className="sr-only"
          id="attachment-input"
          onChange={(e) => onPick(e.target.files)}
        />
        <Button
          variant="outline"
          size="sm"
          disabled={upload.isPending}
          onClick={() => input.current?.click()}
        >
          <Upload />
          {upload.isPending ? "Uploading…" : "Upload file"}
        </Button>
      </div>

      {error && (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      )}

      {files.isPending ? (
        <Skeleton className="h-10" />
      ) : files.isError ? (
        <p className="text-xs text-destructive">{files.error.message}</p>
      ) : files.data.length === 0 ? (
        <p className="rounded-md border border-dashed py-5 text-center text-xs text-muted-foreground">
          No files yet — up to 4 MB each.
        </p>
      ) : (
        <ul className="grid divide-y rounded-md border">
          {files.data.map((file) => (
            <li key={file.id} className="flex items-center gap-3 px-3 py-2">
              <FileText className="size-4 shrink-0 text-muted-foreground" />
              <div className="grid min-w-0 flex-1">
                <span className="truncate text-sm">{file.filename}</span>
                <span className="text-xs text-muted-foreground">
                  {formatSize(file.size)}
                </span>
              </div>
              <Button variant="ghost" size="icon" className="size-8" asChild>
                <a
                  href={api.attachmentUrl(file.id)}
                  aria-label={`Download ${file.filename}`}
                >
                  <Download />
                </a>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="size-8 text-muted-foreground hover:text-destructive"
                aria-label={`Delete ${file.filename}`}
                disabled={remove.isPending}
                onClick={() => remove.mutate(file.id)}
              >
                <Trash2 />
              </Button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/** Notion's "peek": the meeting opens in a panel on the right, over a dimmed page. */
export function MeetingPeek({
  meeting,
  onClose,
}: {
  meeting: Meeting;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const [errors, setErrors] = useState<FieldErrors>({});
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const mutation = useMutation({
    mutationFn: (patch: MeetingPatch) => api.updateMeeting(meeting.id, patch),
    onSuccess: () => {
      setSaved(true);
      return queryClient.invalidateQueries({
        queryKey: ["meetings"],
        exact: true,
      });
    },
    onError: (error) => setErrors({ form: error.message }),
  });

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaved(false);
    const { payload, errors } = validateMeeting(
      new FormData(event.currentTarget),
    );
    setErrors(errors);
    if (!payload) return;
    const patch = diff(meeting, payload);
    if (Object.keys(patch).length === 0) return setSaved(true);
    mutation.mutate(patch);
  }

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div
        aria-hidden
        className="absolute inset-0 bg-house/30 backdrop-blur-[1px]"
        onClick={onClose}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Edit ${meeting.title}`}
        className="relative flex h-full w-full max-w-xl flex-col overflow-y-auto border-l bg-background shadow-2xl"
      >
        <div className="sticky top-0 z-10 flex items-center justify-between border-b bg-background/90 px-6 py-2 backdrop-blur">
          <span className="text-xs text-muted-foreground">Meeting</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-8"
            aria-label="Close"
            onClick={onClose}
          >
            <X />
          </Button>
        </div>

        <div className="grid gap-8 px-6 py-6 sm:px-10">
          {/* key: re-mount the inputs when the meeting changes underneath */}
          <form
            key={`${meeting.id}-${meeting.starts_at}-${meeting.ends_at}-${meeting.title}`}
            onSubmit={onSubmit}
            noValidate
            className="grid gap-3"
          >
            <MeetingFields
              idPrefix={`edit-${meeting.id}`}
              defaults={meeting}
              errors={errors}
            />
            {errors.form && (
              <p role="alert" className="text-sm text-destructive">
                {errors.form}
              </p>
            )}
            <div className="flex items-center justify-end gap-3 pt-1">
              {saved && !mutation.isPending && (
                <span role="status" className="text-xs text-up">
                  Saved
                </span>
              )}
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending ? "Saving…" : "Save changes"}
              </Button>
            </div>
          </form>

          <Files meetingId={meeting.id} />
        </div>
      </div>
    </div>
  );
}
