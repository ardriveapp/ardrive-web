# ArweaveFS - Emulating File Systems on Arweave

ArweaveFS is a data model designed to emulate file systems on Arweave.

Due to Arweave's permanent, immutable nature traditional file system operations such as file/folder renaming and moving, and file updates cannot be done by simply updating the on-chain data model. ArweaveFS works around this by defining an append only transaction data model that allows the state of the file system to be constructed on the client.

## Data Model

ArweaveFS defines several entities for storing file system state on Arweave. These entities have their data split between being stored as tags on their transaction or encoded as JSON as the data of their transaction.

Data stored as transaction tags will be defined in the following manner:

```
Example-Tag: "example-data"
```

while data stored as JSON in the transaction will be defined in the following manner:

```
{
    "exampleField": "exampleData"
}
```

Fields suffixed with `?` are optional.

All transactions that store these entities should define a `Content-Type` transaction tag with value `application/json`.

### Drive

A drive is a logical grouping of folders and files. All folders and files must be part of a drive.

When creating a drive, a corresponding folder should be created as well. This folder will act as the root folder of the drive. This seperation of drive and folder entity concerns enables features such as folder view queries.

```
Drive-Id: <uuid>
Entity-Type: drive
Unix-Time: <unix timestamp>

{
    "rootFolderId": "<uuid of the drive root folder>"
}
```

### Folder

Folder entities without a parent folder id are the root folder of their corresponding drives.

```
Folder-Id: <uuid>
Drive-Id: <drive uuid>
Parent-Folder-Id?: <parent folder uuid>
Entity-Type: folder
Unix-Time: <unix timestamp>

{
    "name": "<user defined folder name>"
}
```

### File

File entity transactions should not include the actual file data they represent, instead, the file data should be uploaded as a separate transaction. This allows for file metadata to be updated without requiring the file data to be reuploaded.

```
File-Id: <uuid>
Drive-Id: <drive uuid>
Parent-Folder-Id: <parent folder uuid>
Entity-Type: file
Unix-Time: <unix timestamp>

{
    "name": "<user defined file name>",
    "size": "<computed file size>",
    "dataTxId": "<transaction id of stored data>"
}
```

## Updating and Constructing the File System State

To update the file system clients can simply create transactions for the entities they would like to update, making sure to specify the same entity id as the update target. For example, to move a folder to another folder, the client can create a transaction with that same folder entity's fields pointing to a different parent folder.

Clients can then create a timeline of entity write transactions which the client can replay to construct the drive state. This timeline of transactions should be grouped by the block number of each transaction. At every step of the timeline, the client can check if the entity was written by an authorised user. This also conveniently enables the client to surface a trusted entity version history to the user.

The `Unix-Time` defined on each transaction should be reserved for tie-breaking same entity updates in the same block and should not be trusted as the source of truth for entity write ordering. This is unimportant for single owner drives but is crucial for multi-owner drives with updateable permissions (currently undefined in this spec) as a malicious user could fake the `Unix-Time` to modify the drive timeline for other users.

ArweaveFS utilises a bottom-up data model (files refer to parent folder, folders refer their parent folder etc) to avoid race conditions in file system updates. A top-down data model would require the parent model (ie. a folder) to store references to its children. When multiple users update the parent entity with new children, there's no way to do so in a consistent manner as a user's update to the parent model will not be seen by another user until the transaction has been mined.

## Additional Client Concerns

### Folder/File Paths

ArweaveFS does not store folder or file paths along with entities as these paths will need to be updated whenever the parent folder name changes which can require many updates for deeply nested file systems. Instead, folder/file paths are left for the client to generate from the folder/file names.

### Client Syncing

Drives that have been updated many times can have a long entity timeline which can be a performance bottleneck. To avoid this clients can cache the drive state locally and sync updates to the file system by only querying for entities in blocks higher than the last time they checked.

### Folder View Queries

Clients that want to provide users with a quick view of a single folder can simply query for an entity timeline for a particular folder by its id. Clients with multi-owner permissions will additionally have to query for the folder's parent drive entity for permission based filtering of the timeline.

## Future Work

### Multi-User Dynamic Permissioned Drives

A drive should be able to have a dynamic set of users that are able to write to it. This will take advantage of the entity timeline for filtering of malicious/invalid entities.

### Private Drives

Folder/file metadata and file contents can be encrypted to enable the use of private drives. For this to work with dynamic permissioned drives there needs to be a way for users to share encryption keys with each other every time the drive permissions are updated. All data that was previously shared with a user will unavoidably be forever accessible to them as long as they retain the encryption key.
