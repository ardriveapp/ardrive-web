# Arweave File System "ArFS" (version 0.11)

ArweaveFS is a data model designed to emulate file systems on Arweave.

Due to Arweave's permanent, immutable nature traditional file system operations such as file/folder renaming and moving, and file updates cannot be done by simply updating the on-chain data model. ArweaveFS works around this by defining an append only transaction data model that allows the state of the file system to be constructed on the client.

## Entity Data Model

ArweaveFS defines several entities for storing file system state on Arweave. These entities have their data split between being stored as tags on their transaction or encoded as JSON as the data of their transaction.  

Drive entities require a single metadata transaction, with standard Drive tags and encoded JSON with secondary metadata.
Folder entities require a single metadata transaction, with standard Folder tags and an encoded JSON with secondary metadata.
File entities require a metadata transaction, with standard File tags an en encoded JSON with secondary metadata.  
File entities also require a second data transaction, which includes a limited set of File tags and the actual file data itself.

MetaData stored in any transaction tags will be defined in the following manner:

```
Example-Tag: "example-data"
```

While MetaData stored any JSON in the transaction will be defined in the following manner:

```
{
    "exampleField": "exampleData"
}
```

Fields suffixed with `?` are optional.

Field enum values are defined in the format "value 1 | value 2".

All metadata transactions that store these entities unencrypted should define a `Content-Type` tag with value `application/json` and an `ArFS` tag with the version of ArFS specification it implements, currently `0.11`.  

## Drive Privacy

Drives can store either public or private data, indicated by the `Drive-Privacy` tag on the drive entity.

If a Drive entity is private, an additional tag `Drive-Auth-Mode` is used to indicate how the Drive Key is derived.  ArDrive clients currently leverage a secure `password` along with the Arweave Wallet private key signature to derive the global Drive key.

On every encrypted entity, a `Cipher` tag must be specified. The required public parameters for decrypting the data must also be specified with the parameter's tag name prefixed by `Cipher-*` eg. `Cipher-IV`. If the parameter is byte data it should be encoded as Base64 in the tag.  ArDrive clients currently leverage AES256-GCM for all symmetric encryption, which requires a Cipher Initialization Vector consisting of 12 random bytes.

Additionally, all encrypted transactions should have the `Content-Type` tag `application/octet-stream` as opposed to `application/json`.

Private drives have a global drive key, `D`, and multiple file keys, `F`, for encryption. `D` is used for encrypting both Drive and Folder metadata whereas `F` is used for encrypting File metadata and the actual stored data. Having these different keys, `D` and `F`, allows a user to share specific files without revealing the contents of their entire drive.

`D` is derived using HKDF-SHA256 with an unsalted RSA-PSS signature of the drive's id and a user provided password. `F` is also derived using HKDF-SHA256 with the drive key and the file's id. A reference implementation is available [here](private_drive_kdf_reference.dart).

### Drive

A Drive is a logical grouping of folders and files. All folders and files must be part of a drive, and reference the Drive ID.

When creating a Drive, a corresponding folder must be created as well. This folder will act as the Drive Root Folder. This seperation of drive and folder entity enables features such as folder view queries.

```
ArFS: 0.11
Cipher?: AES256-GCM
Cipher-IV?: <12 byte initialization vector as hex>
Content-Type: <application/json | application/octet-stream>
Drive-Id: <uuid>
Drive-Privacy: <public | private>
Drive-Auth-Mode?: password
Entity-Type: drive
Unix-Time: <seconds since unix epoch>

{
    "name": "<user defined drive name>",
    "rootFolderId": "<uuid of the drive root folder>"
}
```

### Folder

A Folder is a logical grouping of other folders and files.  Folder entity metadata transactions without a parent folder id are considered the Drive Root Folder of their corresponding Drives.  All other Folder entities must have a parent folder id.  Since folders do not have underlying data, there is no Folder data transaction required.

```
ArFS: 0.11
Cipher?: AES256-GCM
Cipher-IV?: <12 byte initialization vector as Base64>
Content-Type: <application/json | application/octet-stream>
Drive-Id: <drive uuid>
Entity-Type: folder
Folder-Id: <uuid>
Parent-Folder-Id?: <parent folder uuid>
Unix-Time: <seconds since unix epoch>

{
    "name": "<user defined folder name>"
}
```

### File

A File contains actual data, like a photo, document or movie.  File entity metadata transactions do no include the actual File data they represent.  Instead, the File data must  be uploaded as a separate transaction, called the File data transaction. The File metadata transaction JSON references the File data transaction for retrieval.  This separation allows for file metadata to be updated without requiring the file data to be reuploaded.

``` File MetaData Transaction
ArFS: 0.11
Cipher?: AES256-GCM
Cipher-IV?: <12 byte initialization vector as hex>
Content-Type: <application/json | application/octet-stream>
Drive-Id: <drive uuid>
Entity-Type: file
File-Id: <uuid>
Parent-Folder-Id: <parent folder uuid>
Unix-Time: <seconds since unix epoch>

{
    "name": "<user defined file name with extension eg. happyBirthday.jpg>",
    "size": <computed file size - int>,
    "lastModifiedDate": <timestamp for OS reported time of file's last modified date represented as milliseconds since unix epoch - int>
    "dataTxId": "<transaction id of stored data>",
    "dataContentType": "<the mime type of the data associated with this file entity>"
}
```

The File data transaction contains limited information about the file, such as the information required to decrypt it or the Content-Type (mime-type) needed to view in the browser.
``` File Data Transaction
Cipher?: AES256-GCM
Cipher-IV?: <12 byte initialization vector as hex>
Content-Type: <file mime-type | application/octet-stream>
 { File data }
```

## Creating a Drive

To properly create a new drive, two new entities need to be created, a new Drive entity and a new Folder entity representing the root folder of that drive.

The `name` of the drive and folder entity should be the same. The drive entity's `rootFolderId` should refer to the `Folder-Id` of the root folder entity. The folder entity should not include a `Parent-Folder-Id` tag.

The Drive's privacy settings must also be determined in order for its subfolders and files to have the right security settings.

## Updating and Constructing the File System State

To update the file system clients can simply create transactions for the entities they would like to update, making sure to specify the same entity id as the update target. For example, to move a folder to another folder, the client can create a transaction with that same folder entity's fields pointing to a different parent folder.

Clients can then create a timeline of entity write transactions which the client can replay to construct the Drive state. This timeline of transactions should be grouped by the block number of each transaction. At every step of the timeline, the client can check if the entity was written by an authorised user. This also conveniently enables the client to surface a trusted entity version history to the user.

The `Unix-Time` defined on each transaction should be reserved for tie-breaking same entity updates in the same block and should not be trusted as the source of truth for entity write ordering. This is unimportant for single owner drives but is crucial for multi-owner drives with updateable permissions (currently undefined in this spec) as a malicious user could fake the `Unix-Time` to modify the drive timeline for other users.

ArweaveFS utilises a bottom-up data model (files refer to parent folder, folders refer their parent folder etc) to avoid race conditions in file system updates. A top-down data model would require the parent model (ie. a folder) to store references to its children. When multiple users update the parent entity with new children, there's no way to do so in a consistent manner as a user's update to the parent model will not be seen by another user until the transaction has been mined.

## Extending the Arweave File System Schema

Web app and clients can extend the ArFS Schema as needed by adding additional tags into the File and Folder MetaData Transaction JSON.  This gives Developers additional flexibility to support specific application needs, without breaking the overall data model or impacting privacy.  

For example a Music Sharing App could use the following expanded File Metadata for specific music files.

``` Expanded File MetaData Transaction JSON Example
{
    "name": "<user defined file name>",
    "size": <computed file size - int>,
    "lastModifiedDate": <timestamp for OS reported time of file's last modified date represented as milliseconds since unix epoch - int>
    "dataTxId": "<transaction id of stored data>",
    "dataContentType": "<the mime type of the data associated with this file entity>"
    "bandName": "<the name of the band/artist>"
    "bandAlbum": "<the album of the band/artist>"
    "albumSong": "<the title of the song>"
}
```
Additionally, the above extended MetaData fields could be added directly as a transaction tag as well, in order to support GraphQL queries.  However, it is important to not overload transaction tags for optimal performance.

## Additional Client Concerns

### Folder/File Paths

ArweaveFS does not store folder or file paths along with entities as these paths will need to be updated whenever the parent folder name changes which can require many updates for deeply nested file systems. Instead, folder/file paths are left for the client to generate from the folder/file names.

### Client Syncing

Drives that have been updated many times can have a long entity timeline which can be a performance bottleneck. To avoid this clients can cache the drive state locally and sync updates to the file system by only querying for entities in blocks higher than the last time they checked.

### Folder View Queries

Clients that want to provide users with a quick view of a single folder can simply query for an entity timeline for a particular folder by its id. Clients with multi-owner permissions will additionally have to query for the folder's parent drive entity for permission based filtering of the timeline.

## Future Work

### Multi-User Dynamic Permissioned Drives

A drive can have a dynamic set of users that are able to write to it. This will take advantage of the entity timeline for filtering of malicious/invalid entities.

This is achievable relatively easily for public drives but is much more complicated for private drives due to the need to share keys asynchronously. An implementation can draw inspiration from the Signal protocol on how to achieve this.

[kdf]: https://en.wikipedia.org/wiki/Key_derivation_function
