package dev.soupy.eclipse.android.ui.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import dev.soupy.eclipse.android.data.ScheduleRepository
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.ScheduleEntryCard
import dev.soupy.eclipse.android.core.model.ScheduleMode
import dev.soupy.eclipse.android.feature.schedule.ScheduleScreenState

class AndroidScheduleViewModel(
    private val repository: ScheduleRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(ScheduleScreenState(isLoading = true))
    val state: StateFlow<ScheduleScreenState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh(
        localTimeZone: Boolean = true,
        mode: ScheduleMode = _state.value.selectedMode,
    ) {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, errorMessage = null) }
            repository.loadSchedule(mode = mode, localTimeZone = localTimeZone)
                .onSuccess { sections ->
                    _state.value = ScheduleScreenState(
                        isLoading = false,
                        showLocalScheduleTime = localTimeZone,
                        useClassicScheduleUI = _state.value.useClassicScheduleUI,
                        selectedMode = mode,
                        days = sections,
                    )
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = error.message ?: "Unknown schedule error.",
                        )
                    }
                }
        }
    }

    fun selectMode(mode: ScheduleMode) {
        refresh(
            localTimeZone = _state.value.showLocalScheduleTime,
            mode = mode,
        )
    }

    fun select(card: ScheduleEntryCard, onResolved: (DetailTarget) -> Unit) {
        viewModelScope.launch {
            _state.update { it.copy(loadingItemId = card.id, noTmdbEntryTitle = null) }
            repository.lookupTmdbTarget(card)
                .onSuccess { target ->
                    if (target == null) {
                        _state.update { it.copy(loadingItemId = null, noTmdbEntryTitle = card.title) }
                    } else {
                        _state.update { it.copy(loadingItemId = null) }
                        onResolved(target)
                    }
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(
                            loadingItemId = null,
                            errorMessage = error.message ?: "Unable to resolve this schedule entry.",
                        )
                    }
                }
        }
    }

    fun dismissNoTmdbEntry() {
        _state.update { it.copy(noTmdbEntryTitle = null) }
    }
}


