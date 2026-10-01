import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";

import { MeetingFields } from "@/components/meeting-fields";
import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";
import { validateMeeting, type FieldErrors } from "@/lib/meeting-validation";

export function MeetingForm({ onDone }: { onDone: () => void }) {
  const queryClient = useQueryClient();
  const [errors, setErrors] = useState<FieldErrors>({});

  const mutation = useMutation({
    mutationFn: api.createMeeting,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["meetings"] }),
  });

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const { payload, errors } = validateMeeting(
      new FormData(event.currentTarget),
    );
    setErrors(errors);
    if (!payload) return;
    mutation.mutate(payload, {
      onSuccess: onDone,
      onError: (error) => setErrors({ form: error.message }),
    });
  }

  return (
    <form
      onSubmit={onSubmit}
      noValidate
      aria-label="New meeting"
      className="grid gap-3 rounded-lg border bg-card p-5 shadow-[0_1px_2px_rgb(0_0_0/0.04)]"
    >
      <MeetingFields idPrefix="new" errors={errors} />

      {errors.form && (
        <p role="alert" className="text-sm text-destructive">
          {errors.form}
        </p>
      )}

      <div className="flex justify-end gap-2 pt-1">
        <Button type="button" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
        <Button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? "Saving…" : "Add meeting"}
        </Button>
      </div>
    </form>
  );
}
