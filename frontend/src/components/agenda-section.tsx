import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ListChecks,
  ListOrdered,
  Pencil,
  Plus,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import {
  useEffect,
  useRef,
  useState,
  type ComponentProps,
  type Dispatch,
  type FormEvent,
  type SetStateAction,
} from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  MAX_PASTE_CHARS,
  api,
  parserEnabled,
  type ActionItem,
  type Agenda,
  type AgendaItem,
  type Meeting,
  type MeetingPatch,
  type ParseResult,
} from "@/lib/api";
import { cn } from "@/lib/utils";

/* --- form state ---------------------------------------------------------------
 * Every value the parser filled carries a "suggested" flag until the user
 * touches that field. Empty fields stay empty: the parser was told to leave out
 * what the text does not say, and the form must not fill the gap either.
 */

type Row<T> = { key: number; value: T; suggested: Set<keyof T> };

let nextKey = 0;
function row<T extends object>(value: T, fromModel = false): Row<T> {
  const suggested = new Set<keyof T>();
  if (fromModel)
    for (const [field, v] of Object.entries(value))
      if (v !== null && v !== "") suggested.add(field as keyof T);
  return { key: nextKey++, value, suggested };
}

const EMPTY_ITEM: AgendaItem = { topic: "", owner: null, minutes: null };
const EMPTY_ACTION: ActionItem = { task: "", owner: null, due: null };

function SuggestedBadge() {
  return (
    <span className="inline-flex items-center gap-0.5 rounded bg-tint-gold px-1.5 py-0.5 text-[10px] font-medium text-foreground/80">
      <Sparkles className="size-3" />
      suggested
    </span>
  );
}

function Field({
  label,
  suggested,
  className,
  ...input
}: {
  label: string;
  suggested: boolean;
} & ComponentProps<typeof Input>) {
  return (
    <label
      className={cn("grid gap-1 text-xs text-muted-foreground", className)}
    >
      <span className="flex h-4 items-center gap-1.5">
        {label}
        {suggested && <SuggestedBadge />}
      </span>
      <Input
        className={cn("h-8", suggested && "border-gold bg-tint-gold/30")}
        {...input}
      />
    </label>
  );
}

function blank(s: string): string | null {
  const trimmed = s.trim();
  return trimmed === "" ? null : trimmed;
}

/** The meeting fields the parser found, as a PATCH - only what actually changes. */
function meetingPatch(meeting: Meeting, parsed: ParseResult): MeetingPatch {
  const { title, starts_at, duration_minutes } = parsed.agenda;
  const patch: MeetingPatch = {};
  if (title && title.trim() !== meeting.title) patch.title = title.trim();
  const start = starts_at ? new Date(starts_at) : new Date(meeting.starts_at);
  const length = duration_minutes
    ? duration_minutes * 60_000
    : Date.parse(meeting.ends_at) - Date.parse(meeting.starts_at);
  const end = new Date(start.getTime() + length);
  if (Number.isNaN(start.getTime())) return patch;
  if (start.getTime() !== Date.parse(meeting.starts_at))
    patch.starts_at = start.toISOString();
  if (end.getTime() !== Date.parse(meeting.ends_at))
    patch.ends_at = end.toISOString();
  return patch;
}

function describePatch(patch: MeetingPatch): string {
  const parts: string[] = [];
  if (patch.title) parts.push(`title “${patch.title}”`);
  const when = (iso: string) =>
    new Date(iso).toLocaleString(undefined, {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
    });
  if (patch.starts_at) parts.push(`starts ${when(patch.starts_at)}`);
  if (patch.ends_at) parts.push(`ends ${when(patch.ends_at)}`);
  return parts.join(", ");
}

/* --- the pre-filled (or empty) agenda form ---------------------------------- */

function AgendaForm({
  meeting,
  initial,
  parsed,
  onDone,
}: {
  meeting: Meeting;
  initial: Agenda | null;
  parsed: ParseResult | null;
  onDone: () => void;
}) {
  const queryClient = useQueryClient();
  const fromModel = parsed !== null;
  const source = parsed?.agenda ?? initial;
  const [items, setItems] = useState(() =>
    (source?.items.length ? source.items : [EMPTY_ITEM]).map((i) =>
      row(i, fromModel),
    ),
  );
  const [actions, setActions] = useState(() =>
    (source?.action_items ?? []).map((a) => row(a, fromModel)),
  );
  const patch = parsed ? meetingPatch(meeting, parsed) : {};
  const hasPatch = Object.keys(patch).length > 0;
  const [applyPatch, setApplyPatch] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = useMutation({
    mutationFn: async () => {
      const cleanItems = items
        .map(({ value }) => ({ ...value, topic: value.topic.trim() }))
        .filter((i) => i.topic !== "" || i.owner || i.minutes);
      const cleanActions = actions
        .map(({ value }) => ({ ...value, task: value.task.trim() }))
        .filter((a) => a.task !== "" || a.owner || a.due);
      if (cleanItems.some((i) => i.topic === ""))
        throw new Error("Every agenda item needs a topic.");
      if (cleanActions.some((a) => a.task === ""))
        throw new Error("Every action item needs a task.");
      if (applyPatch && hasPatch) await api.updateMeeting(meeting.id, patch);
      return api.saveAgenda(meeting.id, {
        items: cleanItems,
        action_items: cleanActions,
        ai_suggestion: parsed,
      });
    },
    onSuccess: async (agenda) => {
      queryClient.setQueryData(["meetings", meeting.id, "agenda"], agenda);
      await queryClient.invalidateQueries({
        queryKey: ["meetings"],
        exact: true,
      });
      onDone();
    },
    onError: (e) => setError(e.message),
  });

  function edit<T>(
    set: Dispatch<SetStateAction<Row<T>[]>>,
    key: number,
    field: keyof T,
    value: T[keyof T],
  ) {
    set((rows) =>
      rows.map((r) => {
        if (r.key !== key) return r;
        const suggested = new Set(r.suggested);
        suggested.delete(field); // touched: the user owns this value now
        return { ...r, value: { ...r.value, [field]: value }, suggested };
      }),
    );
  }

  function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    save.mutate();
  }

  return (
    <form onSubmit={onSubmit} noValidate className="grid gap-4">
      {fromModel && (
        <p className="rounded-md bg-tint-gold/40 px-3 py-2 text-xs text-foreground/80">
          <Sparkles className="mr-1 inline size-3.5" />
          Suggested by {parsed.model.replace(/^[a-z]+\./, "")} - check every
          marked field before saving. Empty means the text did not say.
        </p>
      )}

      <fieldset className="grid gap-3">
        <legend className="mb-2 inline-flex items-center gap-1.5 text-xs font-semibold text-muted-foreground uppercase">
          <ListOrdered className="size-3.5" /> Items
        </legend>
        {items.map((r, index) => (
          <div
            key={r.key}
            className="grid grid-cols-[1fr_auto] items-end gap-2 sm:grid-cols-[minmax(0,1fr)_9rem_5rem_auto]"
          >
            <Field
              label={`${index + 1}. Topic`}
              suggested={r.suggested.has("topic")}
              value={r.value.topic}
              maxLength={500}
              onChange={(e) => edit(setItems, r.key, "topic", e.target.value)}
              className="col-span-2 sm:col-span-1"
            />
            <Field
              label="Owner"
              suggested={r.suggested.has("owner")}
              value={r.value.owner ?? ""}
              maxLength={200}
              onChange={(e) =>
                edit(setItems, r.key, "owner", blank(e.target.value))
              }
            />
            <Field
              label="Minutes"
              type="number"
              min={1}
              max={480}
              suggested={r.suggested.has("minutes")}
              value={r.value.minutes ?? ""}
              onChange={(e) =>
                edit(
                  setItems,
                  r.key,
                  "minutes",
                  e.target.value === ""
                    ? null
                    : Math.min(480, Math.max(1, Math.round(+e.target.value))),
                )
              }
            />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="size-8 text-muted-foreground hover:text-destructive"
              aria-label={`Remove item ${index + 1}`}
              onClick={() =>
                setItems((rows) => rows.filter((x) => x.key !== r.key))
              }
            >
              <Trash2 />
            </Button>
          </div>
        ))}
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="justify-self-start"
          disabled={items.length >= 50}
          onClick={() => setItems((rows) => [...rows, row(EMPTY_ITEM)])}
        >
          <Plus /> Add item
        </Button>
      </fieldset>

      <fieldset className="grid gap-3">
        <legend className="mb-2 inline-flex items-center gap-1.5 text-xs font-semibold text-muted-foreground uppercase">
          <ListChecks className="size-3.5" /> Action items
        </legend>
        {actions.map((r, index) => (
          <div
            key={r.key}
            className="grid grid-cols-[1fr_auto] items-end gap-2 sm:grid-cols-[minmax(0,1fr)_9rem_9rem_auto]"
          >
            <Field
              label="Task"
              suggested={r.suggested.has("task")}
              value={r.value.task}
              maxLength={500}
              onChange={(e) => edit(setActions, r.key, "task", e.target.value)}
              className="col-span-2 sm:col-span-1"
            />
            <Field
              label="Owner"
              suggested={r.suggested.has("owner")}
              value={r.value.owner ?? ""}
              maxLength={200}
              onChange={(e) =>
                edit(setActions, r.key, "owner", blank(e.target.value))
              }
            />
            <Field
              label="Due"
              type="date"
              suggested={r.suggested.has("due")}
              value={r.value.due ?? ""}
              onChange={(e) =>
                edit(setActions, r.key, "due", e.target.value || null)
              }
            />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="size-8 text-muted-foreground hover:text-destructive"
              aria-label={`Remove action item ${index + 1}`}
              onClick={() =>
                setActions((rows) => rows.filter((x) => x.key !== r.key))
              }
            >
              <Trash2 />
            </Button>
          </div>
        ))}
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="justify-self-start"
          disabled={actions.length >= 50}
          onClick={() => setActions((rows) => [...rows, row(EMPTY_ACTION)])}
        >
          <Plus /> Add action item
        </Button>
      </fieldset>

      {hasPatch && (
        <label className="flex items-start gap-2 rounded-md border border-dashed px-3 py-2 text-xs">
          <input
            type="checkbox"
            className="mt-0.5"
            checked={applyPatch}
            onChange={(e) => setApplyPatch(e.target.checked)}
          />
          <span>
            Also update the meeting: {describePatch(patch)} <SuggestedBadge />
          </span>
        </label>
      )}

      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}
      <div className="flex justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
        <Button type="submit" disabled={save.isPending}>
          {save.isPending ? "Saving…" : "Save agenda"}
        </Button>
      </div>
    </form>
  );
}

/* --- paste, wait, cancel ---------------------------------------------------- */

function PasteBox({
  onParsed,
  onTypeInstead,
}: {
  onParsed: (result: ParseResult) => void;
  onTypeInstead: () => void;
}) {
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const controller = useRef<AbortController | null>(null);

  const parse = useMutation({
    mutationFn: (pasted: string) => {
      controller.current = new AbortController();
      return api.parseAgenda(pasted, controller.current.signal);
    },
    onSuccess: onParsed,
    onError: (e) => {
      if (e.name !== "AbortError") setError(e.message);
    },
  });

  // A second counter while waiting: 2-8 s of nothing feels broken.
  useEffect(() => {
    if (!parse.isPending) return;
    const started = Date.now();
    const timer = window.setInterval(
      () => setElapsed(Math.floor((Date.now() - started) / 1000)),
      250,
    );
    return () => window.clearInterval(timer);
  }, [parse.isPending]);
  // Closing the panel mid-parse stops paying for an answer nobody will read.
  useEffect(() => () => controller.current?.abort(), []);

  const tooLong = text.length > MAX_PASTE_CHARS;

  function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setElapsed(0);
    if (!text.trim()) return setError("Paste the agenda text first.");
    if (tooLong) return;
    parse.mutate(text);
  }

  return (
    <form onSubmit={onSubmit} className="grid gap-2">
      <label htmlFor="paste-agenda" className="text-xs text-muted-foreground">
        Paste an email, a chat message or notes. The model suggests, you check
        and save.
      </label>
      <textarea
        id="paste-agenda"
        rows={7}
        value={text}
        disabled={parse.isPending}
        onChange={(e) => setText(e.target.value)}
        placeholder="Пн 10:00, синк по прайсингу, 45 хв. 1) нові тарифи Pro — Олена, 15 хв 2) …"
        aria-invalid={tooLong || undefined}
        className="w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-xs outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:opacity-60 aria-invalid:border-destructive"
      />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span
          className={cn(
            "text-xs",
            tooLong ? "text-destructive" : "text-muted-foreground",
          )}
        >
          {text.length.toLocaleString("en")} /{" "}
          {MAX_PASTE_CHARS.toLocaleString("en")}
        </span>
        <div className="flex items-center gap-2">
          {parse.isPending ? (
            <>
              <span role="status" className="text-xs text-muted-foreground">
                <Sparkles className="mr-1 inline size-3.5 animate-pulse" />
                Reading the agenda… {elapsed}s
              </span>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => controller.current?.abort()}
              >
                <X /> Cancel
              </Button>
            </>
          ) : (
            <>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={onTypeInstead}
              >
                Type it instead
              </Button>
              <Button type="submit" size="sm" disabled={tooLong}>
                <Sparkles /> Parse
              </Button>
            </>
          )}
        </div>
      </div>
      {error && (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      )}
    </form>
  );
}

/* --- the section in the meeting panel ---------------------------------------- */

type Mode =
  | { kind: "view" }
  | { kind: "paste" }
  | { kind: "edit"; parsed: ParseResult | null };

export function AgendaSection({ meeting }: { meeting: Meeting }) {
  const [mode, setMode] = useState<Mode>({ kind: "view" });
  const agenda = useQuery({
    queryKey: ["meetings", meeting.id, "agenda"],
    queryFn: () => api.getAgenda(meeting.id),
  });

  return (
    <section aria-labelledby="agenda-heading" className="grid gap-3">
      <div className="flex items-center justify-between gap-2">
        <h3
          id="agenda-heading"
          className="inline-flex items-center gap-1.5 text-sm font-semibold"
        >
          <ListOrdered className="size-4" />
          Agenda
        </h3>
        {mode.kind === "view" && agenda.isSuccess && (
          <div className="flex gap-2">
            {parserEnabled && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => setMode({ kind: "paste" })}
              >
                <Sparkles /> Paste an agenda
              </Button>
            )}
            <Button
              variant="outline"
              size="sm"
              onClick={() => setMode({ kind: "edit", parsed: null })}
            >
              {agenda.data ? <Pencil /> : <Plus />}
              {agenda.data ? "Edit" : "Add agenda"}
            </Button>
          </div>
        )}
      </div>

      {mode.kind === "paste" && (
        <PasteBox
          onParsed={(parsed) => setMode({ kind: "edit", parsed })}
          onTypeInstead={() => setMode({ kind: "edit", parsed: null })}
        />
      )}

      {mode.kind === "edit" && (
        <AgendaForm
          meeting={meeting}
          initial={agenda.data ?? null}
          parsed={mode.parsed}
          onDone={() => setMode({ kind: "view" })}
        />
      )}

      {mode.kind === "view" &&
        (agenda.isPending ? (
          <Skeleton className="h-10" />
        ) : agenda.isError ? (
          <p className="text-xs text-destructive">{agenda.error.message}</p>
        ) : !agenda.data ? (
          <p className="rounded-md border border-dashed py-5 text-center text-xs text-muted-foreground">
            No agenda yet.
          </p>
        ) : (
          <AgendaView agenda={agenda.data} />
        ))}
    </section>
  );
}

function AgendaView({ agenda }: { agenda: Agenda }) {
  return (
    <div className="grid gap-3 text-sm">
      {agenda.items.length > 0 && (
        <ol className="grid list-decimal gap-1 pl-5">
          {agenda.items.map((item, i) => (
            <li key={i}>
              {item.topic}
              {(item.owner || item.minutes) && (
                <span className="text-muted-foreground">
                  {" "}
                  —{" "}
                  {[item.owner, item.minutes && `${item.minutes} min`]
                    .filter(Boolean)
                    .join(", ")}
                </span>
              )}
            </li>
          ))}
        </ol>
      )}
      {agenda.action_items.length > 0 && (
        <ul className="grid gap-1">
          {agenda.action_items.map((a, i) => (
            <li key={i} className="flex gap-2">
              <ListChecks className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
              <span>
                {a.task}
                {(a.owner || a.due) && (
                  <span className="text-muted-foreground">
                    {" "}
                    —{" "}
                    {[a.owner, a.due && `by ${a.due}`]
                      .filter(Boolean)
                      .join(", ")}
                  </span>
                )}
              </span>
            </li>
          ))}
        </ul>
      )}
      {agenda.ai_model && (
        <p className="text-xs text-muted-foreground">
          <Sparkles className="mr-1 inline size-3" />
          Started from a suggestion ({agenda.ai_prompt_version})
        </p>
      )}
    </div>
  );
}
