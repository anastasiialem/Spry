import { CalendarDays, CircleDot, Clock, Users } from "lucide-react";
import type { ComponentProps, ReactNode } from "react";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { meetingStatuses, type Meeting, type MeetingCreate } from "@/lib/api";
import { toLocalInput, type FieldErrors } from "@/lib/meeting-validation";
import { STATUS } from "@/lib/status";

/** A Notion-style property row: icon + name on the left, value on the right. */
function Property({
  htmlFor,
  icon,
  label,
  error,
  children,
}: {
  htmlFor: string;
  icon: ReactNode;
  label: string;
  error?: string;
  children: ReactNode;
}) {
  return (
    <div className="grid items-start gap-1 sm:grid-cols-[9rem_1fr] sm:gap-3">
      <Label
        htmlFor={htmlFor}
        className="h-9 font-normal text-muted-foreground [&_svg]:size-4"
      >
        {icon}
        {label}
      </Label>
      <div className="grid gap-1">
        {children}
        {error && (
          <p id={`${htmlFor}-error`} className="text-xs text-destructive">
            {error}
          </p>
        )}
      </div>
    </div>
  );
}

function PropertyInput({
  name,
  error,
  ...input
}: { name: keyof MeetingCreate; error?: string } & Omit<
  ComponentProps<typeof Input>,
  "name"
>) {
  return (
    <Input
      name={name}
      aria-invalid={error ? true : undefined}
      aria-describedby={error && input.id ? `${input.id}-error` : undefined}
      className="max-w-xs"
      {...input}
    />
  );
}

/**
 * Title + properties, shared by the create form and the edit panel.
 * `idPrefix` keeps element ids unique when both are on screen.
 */
export function MeetingFields({
  idPrefix,
  defaults,
  errors,
}: {
  idPrefix: string;
  defaults?: Meeting;
  errors: FieldErrors;
}) {
  const id = (name: string) => `${idPrefix}-${name}`;
  return (
    <>
      <div className="grid gap-1">
        <label htmlFor={id("title")} className="sr-only">
          Title
        </label>
        <input
          id={id("title")}
          name="title"
          autoFocus={!defaults}
          maxLength={200}
          defaultValue={defaults?.title}
          placeholder="Untitled meeting"
          aria-invalid={errors.title ? true : undefined}
          className="w-full bg-transparent text-2xl font-bold tracking-tight outline-none placeholder:text-muted-foreground/50"
        />
        {errors.title && (
          <p className="text-xs text-destructive">{errors.title}</p>
        )}
      </div>

      <Property
        htmlFor={id("starts_at")}
        icon={<CalendarDays />}
        label="Starts"
        error={errors.starts_at}
      >
        <PropertyInput
          id={id("starts_at")}
          name="starts_at"
          type="datetime-local"
          defaultValue={defaults && toLocalInput(defaults.starts_at)}
          error={errors.starts_at}
        />
      </Property>
      <Property
        htmlFor={id("ends_at")}
        icon={<Clock />}
        label="Ends"
        error={errors.ends_at}
      >
        <PropertyInput
          id={id("ends_at")}
          name="ends_at"
          type="datetime-local"
          defaultValue={defaults && toLocalInput(defaults.ends_at)}
          error={errors.ends_at}
        />
      </Property>
      <Property
        htmlFor={id("attendee_count")}
        icon={<Users />}
        label="Attendees"
        error={errors.attendee_count}
      >
        <PropertyInput
          id={id("attendee_count")}
          name="attendee_count"
          type="number"
          min={1}
          max={1000}
          defaultValue={defaults?.attendee_count ?? 2}
          error={errors.attendee_count}
        />
      </Property>
      <Property htmlFor={id("status")} icon={<CircleDot />} label="Status">
        <select
          id={id("status")}
          name="status"
          defaultValue={defaults?.status ?? "not_started"}
          className="h-9 w-full max-w-xs rounded-md border border-input bg-transparent px-2.5 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
        >
          {meetingStatuses.map((s) => (
            <option key={s} value={s}>
              {STATUS[s].label}
            </option>
          ))}
        </select>
      </Property>
    </>
  );
}
