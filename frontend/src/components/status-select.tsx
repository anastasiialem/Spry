import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ChevronDown } from "lucide-react";

import {
  api,
  meetingStatuses,
  type Meeting,
  type MeetingStatus,
} from "@/lib/api";
import { STATUS } from "@/lib/status";
import { cn } from "@/lib/utils";

export function StatusPill({
  status,
  className,
}: {
  status: MeetingStatus;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium",
        STATUS[status].pill,
        className,
      )}
    >
      <span className={cn("size-1.5 rounded-full", STATUS[status].dot)} />
      {STATUS[status].label}
    </span>
  );
}

/**
 * The pill is what you see; a transparent native <select> sits on top of it, so the
 * picker is keyboard- and screen-reader-friendly without a popover library.
 */
export function StatusSelect({ meeting }: { meeting: Meeting }) {
  const queryClient = useQueryClient();

  const mutation = useMutation({
    mutationFn: (status: MeetingStatus) =>
      api.updateMeetingStatus(meeting.id, status),
    // Optimistic: change the row now, put it back if the server says no.
    onMutate: async (status) => {
      await queryClient.cancelQueries({ queryKey: ["meetings"] });
      const previous = queryClient.getQueryData<Meeting[]>(["meetings"]);
      queryClient.setQueryData<Meeting[]>(["meetings"], (old) =>
        old?.map((m) => (m.id === meeting.id ? { ...m, status } : m)),
      );
      return { previous };
    },
    onError: (_error, _status, context) => {
      queryClient.setQueryData(["meetings"], context?.previous);
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ["meetings"] }),
  });

  return (
    <span className="inline-flex items-center gap-2">
      <span className="group relative inline-flex">
        <StatusPill
          status={meeting.status}
          className="pr-1.5 group-hover:brightness-95"
        />
        <ChevronDown className="pointer-events-none absolute top-1/2 right-1 hidden size-3 -translate-y-1/2 opacity-60 group-hover:block" />
        <select
          aria-label={`Status of ${meeting.title}`}
          value={meeting.status}
          onChange={(e) => mutation.mutate(e.target.value as MeetingStatus)}
          className="absolute inset-0 cursor-pointer opacity-0"
        >
          {meetingStatuses.map((s) => (
            <option key={s} value={s}>
              {STATUS[s].label}
            </option>
          ))}
        </select>
      </span>
      {mutation.isError && (
        <span role="alert" className="text-xs text-destructive">
          Not saved
        </span>
      )}
    </span>
  );
}
