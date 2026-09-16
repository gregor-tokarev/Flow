package dev.jvqtil.flow.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.dp
import dev.jvqtil.flow.ui.FolderUiModel
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState

@Composable
fun FoldersBar(
    folders: List<FolderUiModel>,
    selectedFolderId: String,
    folderListState: LazyListState,
    onSelectFolder: (String) -> Unit,
    onFolderLongPress: (FolderUiModel) -> Unit,
    onNewFolder: () -> Unit,
    onLocalFoldersChange: (List<FolderUiModel>) -> Unit,
    onDragStarted: (Offset) -> Unit,
    onDragStopped: () -> Unit
) {
    val reorderableState =
        rememberReorderableLazyListState(
            lazyListState = folderListState
        ) { from, to ->
            val fromId = from.key as String
            val toId = to.key as String

            val fromIndex = folders.indexOfFirst {
                it.id == fromId
            }

            val toIndex = folders.indexOfFirst {
                it.id == toId
            }

            if (
                fromIndex >= 0 &&
                toIndex >= 0 &&
                fromIndex != toIndex
            ) {
                onLocalFoldersChange(
                    folders.toMutableList().apply {
                        add(
                            toIndex,
                            removeAt(fromIndex)
                        )
                    }
                )
            }
        }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(38.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier.weight(1f)
        ) {
            LazyRow(
                modifier = Modifier.fillMaxWidth(),
                state = folderListState,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(
                    items = folders,
                    key = { it.id }
                ) { folder ->
                    ReorderableItem(
                        state = reorderableState,
                        key = folder.id
                    ) {
                        FolderItem(
                            folder = folder,
                            selected = folder.id == selectedFolderId,
                            selectedFolderId = selectedFolderId,
                            folders = folders,
                            dragHandleModifier =
                                Modifier.longPressDraggableHandle(
                                    onDragStarted = onDragStarted,
                                    onDragStopped = onDragStopped
                                ),
                            onSelect = { id, _ ->
                                onSelectFolder(id)
                            },
                            onLongPress = onFolderLongPress
                        )
                    }
                }
            }
        }

        Box(
            modifier = Modifier.size(38.dp),
            contentAlignment = Alignment.Center
        ) {
            IconButton(
                onClick = onNewFolder,
                modifier = Modifier.size(38.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null,
                    modifier = Modifier.size(22.dp),
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
        }
    }
}