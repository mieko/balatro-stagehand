import { join } from 'node:path';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { ZipReader, ZipWriter, Uint8ArrayReader, Uint8ArrayWriter } from '@zip.js/zip.js';

// Balatro.exe is a LÖVE executable with a ZIP appended, not a separate .love file.
export async function readZip(filename, read) {
  const reader = new ZipReader(new Uint8ArrayReader(await readFile(filename)), {
    useWebWorkers: false,
  });

  try {
    return await read(await reader.getEntries());
  } finally {
    await reader.close();
  }
}

export async function zipData(entries, name) {
  const entry = entries.find((item) => item.filename === name && !item.directory);

  if (!entry) throw new Error(`Archive has no ${name}`);

  return entry.getData(new Uint8ArrayWriter(), { checkSignature: true });
}

export async function writeZip(filename, files) {
  const writer = new ZipWriter(new Uint8ArrayWriter(), { useWebWorkers: false });

  for (const [name, bytes] of files) {
    await writer.add(name, new Uint8ArrayReader(bytes));
  }

  await writeFile(filename, await writer.close());
}

export async function directoryFiles(directory, prefix) {
  const files = [];

  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const source = join(directory, entry.name);
    const name = prefix + '/' + entry.name;

    if (entry.isDirectory()) files.push(...(await directoryFiles(source, name)));
    else files.push([name, await readFile(source)]);
  }

  return files;
}
