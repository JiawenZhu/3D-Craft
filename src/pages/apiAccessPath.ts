export const API_ACCESS_PATH = '/account/api';
export const isApiAccessPath = (path: string) => path.replace(/\/$/, '') === API_ACCESS_PATH;
