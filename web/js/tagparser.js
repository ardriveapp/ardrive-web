var avro = window.avro;

function serializeTags(tags) {
  const tagSchema = avro.Type.forSchema({
    type: 'record',
    name: 'Tag',
    fields: [
      { name: 'name', type: 'string' },
      { name: 'value', type: 'string' },
    ],
  });

  const tagsSchema = avro.Type.forSchema({
    type: 'array',
    items: tagSchema,
  });
  if (tags.length == 0) {
    return new Uint8Array(0);
  }

  let tagsBuffer;
  try {
    tagsBuffer = tagsSchema.toBuffer(tags);
  } catch (e) {
    console.log(e);
    throw new Error(
      'Incorrect tag format used. Make sure your tags are { name: string!, value: string! }[]',
    );
  }
  return Uint8Array.from(tagsBuffer);
}
