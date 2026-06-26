import type { CollectionEntry } from "astro:content";

type DatedEntry = {
  data: {
    date?: Date;
    dateTime?: Date;
    weekOf?: Date;
    sortOrder?: number;
  };
};

export const newestFirst = <T extends DatedEntry>(items: T[]) =>
  [...items].sort((a, b) => {
    const aDate = a.data.date ?? a.data.dateTime ?? a.data.weekOf ?? new Date(0);
    const bDate = b.data.date ?? b.data.dateTime ?? b.data.weekOf ?? new Date(0);
    return bDate.valueOf() - aDate.valueOf();
  });

export const bySortOrder = <T extends DatedEntry>(items: T[]) =>
  [...items].sort((a, b) => (a.data.sortOrder ?? 100) - (b.data.sortOrder ?? 100));

export const upcomingFirst = <T extends CollectionEntry<"events">>(items: T[]) =>
  [...items].sort((a, b) => a.data.dateTime.valueOf() - b.data.dateTime.valueOf());

export const formatDate = (date: Date, options: Intl.DateTimeFormatOptions = {}) =>
  new Intl.DateTimeFormat("en-AU", {
    day: "numeric",
    month: "short",
    year: "numeric",
    ...options
  }).format(date);

export const formatDateTime = (date: Date) =>
  new Intl.DateTimeFormat("en-AU", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit"
  }).format(date);

export const money = (amount: number) =>
  new Intl.NumberFormat("en-AU", {
    style: "currency",
    currency: "AUD",
    maximumFractionDigits: 0
  }).format(amount);

export const progressPercent = (current: number, goal: number) =>
  Math.min(100, Math.round((current / goal) * 100));
