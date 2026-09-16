package dev.jvqtil.flow.ui.components

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.jvqtil.flow.R
import dev.jvqtil.flow.data.MASTER_FOLDER_ID
import dev.jvqtil.flow.ui.FolderUiModel

@Composable
fun FolderItem(
    folder: FolderUiModel,
    selected: Boolean,
    selectedFolderId: String,
    folders: List<FolderUiModel>,
    dragHandleModifier: Modifier,
    onSelect: (String, Int) -> Unit,
    onLongPress: (FolderUiModel) -> Unit
) {
    val cornerRadius by animateDpAsState(
        targetValue = if (selected) {
            16.dp
        } else {
            14.dp
        },
        animationSpec = tween(200),
        label = "folderCornerRadius"
    )

    val displayName =
        if (
            folder.id == MASTER_FOLDER_ID &&
            folder.name.isBlank()
        ) {
            stringResource(R.string.master_folder_label)
        } else {
            folder.name
        }

    Box(
        modifier = Modifier
            .background(
                color = if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.surfaceContainer
                },
                shape = RoundedCornerShape(cornerRadius)
            )
    ) {
        Row(
            modifier = Modifier.height(38.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .pointerInput(
                        folder.id,
                        selected
                    ) {
                        detectTapGestures(
                            onTap = {
                                if (!selected) {
                                    val currentIndex =
                                        folders.indexOfFirst {
                                            it.id == selectedFolderId
                                        }

                                    val newIndex =
                                        folders.indexOfFirst {
                                            it.id == folder.id
                                        }

                                    val direction =
                                        if (newIndex > currentIndex) {
                                            1
                                        } else {
                                            -1
                                        }

                                    onSelect(
                                        folder.id,
                                        direction
                                    )
                                }
                            },
                            onLongPress = {
                                onLongPress(folder)
                            }
                        )
                    }
                    .padding(
                        start = 16.dp,
                        end = 4.dp
                    ),
                contentAlignment = Alignment.CenterStart
            ) {
                Text(
                    text = displayName,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = if (selected) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                    style = MaterialTheme.typography.labelLarge
                )
            }

            Box(
                modifier = dragHandleModifier
                    .size(28.dp),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.DragIndicator,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = if (selected) {
                        MaterialTheme.colorScheme.onPrimary.copy(
                            alpha = 0.75f
                        )
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(
                            alpha = 0.65f
                        )
                    }
                )
            }

            Spacer(
                modifier = Modifier.width(4.dp)
            )
        }
    }
}