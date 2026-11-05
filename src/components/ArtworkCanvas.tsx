import React, { useMemo } from 'react';

interface ArtworkCanvasProps {
  title: string;
  genre?: string;
  year?: number;
  className?: string;
}

export const ArtworkCanvas: React.FC<ArtworkCanvasProps> = ({
  title,
  genre = 'Action',
  year = 1993,
  className = ''
}) => {
  // Generate deterministic color palette based on title
  const { gradient, accent, patternColor, shapeType } = useMemo(() => {
    let hash = 0;
    for (let i = 0; i < title.length; i++) {
      hash = (hash << 5) - hash + title.charCodeAt(i);
      hash |= 0;
    }
    const hue1 = Math.abs(hash % 360);
    const hue2 = (hue1 + 45 + (Math.abs(hash >> 3) % 90)) % 360;
    const accentHue = (hue1 + 180) % 360;

    return {
      gradient: `linear-gradient(135deg, hsl(${hue1}, 75%, 35%) 0%, hsl(${hue2}, 85%, 15%) 100%)`,
      accent: `hsl(${accentHue}, 90%, 60%)`,
      patternColor: `hsla(${hue1}, 80%, 75%, 0.15)`,
      shapeType: Math.abs(hash) % 3
    };
  }, [title]);

  return (
    <div
      className={`relative overflow-hidden rounded-xl border border-white/10 shadow-lg flex flex-col justify-between p-3.5 select-none ${className}`}
      style={{ background: gradient }}
    >
      {/* Background geometric retro pattern */}
      <div className="absolute inset-0 opacity-40 pointer-events-none">
        <svg width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <pattern id={`grid-${title}`} width="20" height="20" patternUnits="userSpaceOnUse">
              <path d="M 20 0 L 0 0 0 20" fill="none" stroke={patternColor} strokeWidth="1" />
              {shapeType === 0 && <circle cx="10" cy="10" r="2.5" fill={patternColor} />}
              {shapeType === 1 && <rect x="8" y="8" width="4" height="4" fill={patternColor} />}
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill={`url(#grid-${title})`} />
        </svg>
      </div>

      {/* SNES Super Nintendo Header Banner */}
      <div className="relative z-10 flex items-center justify-between pb-2 border-b border-white/20">
        <div className="flex items-center gap-1.5">
          <div className="flex gap-0.5">
            <span className="w-1.5 h-3.5 rounded-xs bg-red-500 transform -skew-x-12" />
            <span className="w-1.5 h-3.5 rounded-xs bg-yellow-400 transform -skew-x-12" />
            <span className="w-1.5 h-3.5 rounded-xs bg-blue-500 transform -skew-x-12" />
            <span className="w-1.5 h-3.5 rounded-xs bg-green-500 transform -skew-x-12" />
          </div>
          <span className="text-[10px] font-black tracking-widest text-white/90 uppercase font-mono">
            SUPER NES
          </span>
        </div>
        <span className="text-[9px] font-semibold text-white/70 font-mono tracking-wider bg-black/40 px-1.5 py-0.5 rounded">
          {year}
        </span>
      </div>

      {/* Center Graphic */}
      <div className="relative z-10 flex-1 flex flex-col items-center justify-center my-3">
        <div
          className="w-16 h-16 rounded-2xl flex items-center justify-center shadow-xl border border-white/30 backdrop-blur-xs transform hover:scale-105 transition-transform"
          style={{ backgroundColor: 'rgba(0,0,0,0.35)' }}
        >
          <span
            className="text-2xl font-black tracking-tighter"
            style={{ color: accent }}
          >
            {title.slice(0, 2).toUpperCase()}
          </span>
        </div>
      </div>

      {/* Bottom Title & Genre */}
      <div className="relative z-10 pt-2 border-t border-white/15 bg-black/30 -mx-3.5 -mb-3.5 px-3.5 py-2.5 rounded-b-xl">
        <p className="text-xs font-black text-white truncate tracking-wide leading-tight uppercase">
          {title}
        </p>
        <p className="text-[9px] font-medium text-white/60 tracking-wider uppercase font-mono mt-0.5">
          {genre}
        </p>
      </div>
    </div>
  );
};
