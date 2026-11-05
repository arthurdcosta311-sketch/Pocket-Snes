export type PadInput =
  | 'up'
  | 'down'
  | 'left'
  | 'right'
  | 'a'
  | 'b'
  | 'x'
  | 'y'
  | 'l'
  | 'r'
  | 'start'
  | 'select';

export enum ButtonMask {
  B = 0x8000,
  Y = 0x4000,
  Select = 0x2000,
  Start = 0x1000,
  Up = 0x0800,
  Down = 0x0400,
  Left = 0x0200,
  Right = 0x0100,
  A = 0x0080,
  X = 0x0040,
  L = 0x0020,
  R = 0x0010
}

export interface GameArt {
  seed: number;
  sky: string;
  land: string;
  sun: string;
  accent: string;
  symbol: string;
}

export interface SaveState {
  id: string;
  slot: number;
  label: string;
  date: string;
  previewUrl?: string;
  data?: string; // base64 or JSON state
}

export interface RetroGame {
  id: string;
  title: string;
  tagline: string;
  blurb: string;
  system: 'SNES';
  year: number;
  players: number;
  region: string;
  fileSize: string;
  playTime: number; // in seconds
  progress: number;
  lastPlayed: string | null;
  isFavorite: boolean;
  saveStates: SaveState[];
  art: GameArt;
  romData?: Uint8Array;
}

export type VideoFilter = 'crisp' | 'smooth' | 'crt';
export type ScreenFit = 'fit' | 'stretch' | 'integer';
export type ControllerSkin = 'snesPocket' | 'classic';
export type LibrarySort = 'recent' | 'alphabetical' | 'mostPlayed';

export interface AppSettings {
  videoFilter: VideoFilter;
  screenFit: ScreenFit;
  scanlines: boolean;
  volume: number;
  muted: boolean;
  controlSkin: ControllerSkin;
  controlOpacity: number;
  haptics: boolean;
  showsShoulders: boolean;
}
