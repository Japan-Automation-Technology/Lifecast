export function ok<T>(result: T) {
  return {
    request_id: crypto.randomUUID(),
    server_time: new Date().toISOString(),
    result,
  };
}

export function fail(code: string, message: string, details?: Record<string, unknown>) {
  return {
    request_id: crypto.randomUUID(),
    server_time: new Date().toISOString(),
    error: {
      code,
      message,
      details,
    },
  };
}
