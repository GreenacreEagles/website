type TimingContext = {
  locals?: any;
};

const safeName = (name: string) => name.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 32);

export const recordServerTiming = (context: TimingContext, name: string, startedAt: number) => {
  const duration = Math.max(0, performance.now() - startedAt);
  context.locals ??= {};
  context.locals.serverTimings ??= [];
  context.locals.serverTimings.push({ name: safeName(name), duration });
};

export const formatServerTimings = (context: TimingContext) =>
  ((context.locals?.serverTimings ?? []) as Array<{ name: string; duration: number }>)
    .map(({ name, duration }: { name: string; duration: number }) => `${name};dur=${duration.toFixed(1)}`)
    .join(", ");
