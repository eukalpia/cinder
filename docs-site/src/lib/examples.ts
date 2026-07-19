import manifest from '@/generated/examples.json';

export type CinderRuntimeMode =
  | 'direct-web'
  | 'browser-adapter'
  | 'browser-sandbox'
  | 'native-only'
  | 'build-failed';

export type CinderExample = {
  slug: string;
  title: string;
  category: string;
  repositoryPath: string;
  sourcePath: string;
  sourceUrl: string;
  adapterSourceUrl?: string | null;
  runnable: boolean;
  bundle: string | null;
  reason: string | null;
  description: string;
  runtimeMode?: CinderRuntimeMode;
  runtimeNote?: string;
  controls?: string[];
  tags?: string[];
};

export type CinderExampleManifest = {
  generatedAt: string;
  version: string;
  documentationCount: number;
  examples: CinderExample[];
};

const typedManifest = manifest as CinderExampleManifest;

export const examples = typedManifest.examples.map(normalizeExample);
export const cinderVersion = typedManifest.version;
export const documentationCount = typedManifest.documentationCount;
export const runnableExamples = examples.filter((example) => example.runnable);
export const exampleCategories = Array.from(
  new Set(examples.map((example) => example.category)),
).sort((left, right) => left.localeCompare(right));
export const exampleRuntimeModes = Array.from(
  new Set(examples.map((example) => example.runtimeMode)),
).sort((left, right) => left.localeCompare(right));

export function getExample(slug: string) {
  return examples.find((example) => example.slug === slug);
}

export function runtimeModeLabel(mode: CinderRuntimeMode) {
  switch (mode) {
    case 'direct-web':
      return 'Direct web';
    case 'browser-adapter':
      return 'Web adapter';
    case 'browser-sandbox':
      return 'Web sandbox';
    case 'native-only':
      return 'Native only';
    case 'build-failed':
      return 'Build failed';
  }
}

export function runtimeModeDescription(mode: CinderRuntimeMode) {
  switch (mode) {
    case 'direct-web':
      return 'The original repository source is compiled and executed in the browser.';
    case 'browser-adapter':
      return 'An official browser capability adapter preserves the Cinder UI and example intent.';
    case 'browser-sandbox':
      return 'A deterministic sandbox demonstrates the UI and state transitions without claiming native access.';
    case 'native-only':
      return 'The example requires a native terminal or operating-system capability.';
    case 'build-failed':
      return 'The source is indexed, but the current web compiler could not create a bundle.';
  }
}

function normalizeExample(example: CinderExample): CinderExample & {
  runtimeMode: CinderRuntimeMode;
  runtimeNote: string;
  controls: string[];
  tags: string[];
} {
  const runtimeMode =
    example.runtimeMode ?? (example.runnable ? 'direct-web' : 'native-only');
  return {
    ...example,
    runtimeMode,
    runtimeNote:
      example.runtimeNote ?? runtimeModeDescription(runtimeMode),
    controls: example.controls ?? [],
    tags: example.tags ?? [example.category.toLowerCase()],
  };
}
