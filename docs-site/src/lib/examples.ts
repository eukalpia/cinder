import manifest from '@/generated/examples.json';

export type CinderExample = {
  slug: string;
  title: string;
  category: string;
  repositoryPath: string;
  sourcePath: string;
  sourceUrl: string;
  runnable: boolean;
  bundle: string | null;
  reason: string | null;
  description: string;
};

export type CinderExampleManifest = {
  generatedAt: string;
  version: string;
  documentationCount: number;
  examples: CinderExample[];
};

const typedManifest = manifest as CinderExampleManifest;

export const examples = typedManifest.examples;
export const cinderVersion = typedManifest.version;
export const documentationCount = typedManifest.documentationCount;
export const runnableExamples = examples.filter((example) => example.runnable);
export const exampleCategories = Array.from(
  new Set(examples.map((example) => example.category)),
).sort((left, right) => left.localeCompare(right));

export function getExample(slug: string) {
  return examples.find((example) => example.slug === slug);
}
