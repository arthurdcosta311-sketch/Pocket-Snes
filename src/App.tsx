import { useState, useMemo } from 'react';
import { SNESCore } from './engine/SNESCore';
import { LibraryView } from './components/LibraryView';
import { PlayerView } from './components/PlayerView';
import { SettingsModal } from './components/SettingsModal';
import { SelfTestModal } from './components/SelfTestModal';

export function App() {
  const core = useMemo(() => new SNESCore(), []);
  const [activeROM, setActiveROM] = useState<{
    data: Uint8Array;
    title: string;
  } | null>(null);

  const [pocketTheme, setPocketTheme] = useState<'us-purple' | 'famicom-color' | 'dark-onyx'>('us-purple');
  const [isSettingsOpen, setIsSettingsOpen] = useState<boolean>(false);
  const [isSelfTestOpen, setIsSelfTestOpen] = useState<boolean>(false);

  const handleLaunchROM = (data: Uint8Array, title: string) => {
    core.loadROM(data);
    setActiveROM({ data, title });
  };

  const handleBackToLibrary = () => {
    setActiveROM(null);
  };

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100 font-sans selection:bg-purple-600 selection:text-white">
      {activeROM ? (
        <PlayerView
          core={core}
          romTitle={activeROM.title}
          onBack={handleBackToLibrary}
          onOpenSettings={() => setIsSettingsOpen(true)}
          pocketTheme={pocketTheme}
        />
      ) : (
        <LibraryView
          onLaunchROM={handleLaunchROM}
          onOpenSelfTest={() => setIsSelfTestOpen(true)}
          onOpenSettings={() => setIsSettingsOpen(true)}
        />
      )}

      {/* Settings Modal */}
      <SettingsModal
        isOpen={isSettingsOpen}
        onClose={() => setIsSettingsOpen(false)}
        pocketTheme={pocketTheme}
        onThemeChange={setPocketTheme}
      />

      {/* Hardware Diagnostics Self Test Modal */}
      <SelfTestModal
        isOpen={isSelfTestOpen}
        onClose={() => setIsSelfTestOpen(false)}
      />
    </div>
  );
}

export default App;
