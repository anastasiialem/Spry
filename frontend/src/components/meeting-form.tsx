import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { useState, type ComponentProps, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api, type MeetingCreate } from "@/lib/api";

type Errors = Partial<Record<keyof MeetingCreate | "form", string>>;

/** "2026-10-05T12:00" in the browser's zone -> "2026-10-05T09:00:00.000Z". */
const toUtc = (local: string) => new Date(local).toISOString();

function validate(form: FormData): { payload?: MeetingCreate; errors: Errors } {
  const title = String(form.get("title") ?? "").trim();
  const start = String(form.get("starts_at") ?? "");
  const end = String(form.get("ends_at") ?? "");
  const count = Number(form.get("attendee_count"));
  const errors: Errors = {};

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
    },
  };
}

function Field({
  id,
  label,
  error,
  ...input
}: { id: keyof MeetingCreate; label: string; error?: string } & Omit<
  ComponentProps<typeof Input>,
  "id" | "name"
>) {
  return (
    <div className="grid gap-2">
      <Label htmlFor={id}>{label}</Label>
      <Input
        id={id}
        name={id}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? `${id}-error` : undefined}
        {...input}
      />
      {error && (
        <p id={`${id}-error`} className="text-xs text-destructive">
          {error}
        </p>
      )}
    </div>
  );
}

export function MeetingForm() {
  const queryClient = useQueryClient();
  const [errors, setErrors] = useState<Errors>({});

  const mutation = useMutation({
    mutationFn: api.createMeeting,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["meetings"] }),
  });

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formEl = event.currentTarget;
    const { payload, errors } = validate(new FormData(formEl));
    setErrors(errors);
    if (!payload) return;
    mutation.mutate(payload, {
      onSuccess: () => formEl.reset(),
      onError: (error) => setErrors({ form: error.message }),
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>New meeting</CardTitle>
        <CardDescription>Times are in your local time zone.</CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={onSubmit} noValidate className="grid gap-4">
          <Field
            id="title"
            label="Title"
            placeholder="Weekly sync"
            maxLength={200}
            error={errors.title}
          />
          <div className="grid gap-4 sm:grid-cols-2">
            <Field
              id="starts_at"
              label="Starts"
              type="datetime-local"
              error={errors.starts_at}
            />
            <Field
              id="ends_at"
              label="Ends"
              type="datetime-local"
              error={errors.ends_at}
            />
          </div>
          <div className="flex flex-wrap items-end gap-4">
            <div className="w-32">
              <Field
                id="attendee_count"
                label="Attendees"
                type="number"
                min={1}
                max={1000}
                defaultValue={2}
                error={errors.attendee_count}
              />
            </div>
            <Button
              type="submit"
              className="ml-auto"
              disabled={mutation.isPending}
            >
              <Plus />
              {mutation.isPending ? "Adding…" : "Add meeting"}
            </Button>
          </div>
          {errors.form && (
            <p role="alert" className="text-sm text-destructive">
              {errors.form}
            </p>
          )}
        </form>
      </CardContent>
    </Card>
  );
}
