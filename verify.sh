#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

case "${1:-}" in
  "") export XQ_RUN_ENGINE_TESTS=0 ;;
  --with-engine)
    export XQ_RUN_ENGINE_TESTS=1
    [[ $# -eq 1 ]] || { printf 'Usage: ./verify.sh [--with-engine]\n' >&2; exit 2; }
    [[ "${XQ_ENGINE_PATH:-}" == /* && -x "$XQ_ENGINE_PATH" && -f "$XQ_ENGINE_PATH" ]] || {
      printf 'Live checks require XQ_ENGINE_PATH pointing to your trusted executable.\n' >&2; exit 2;
    }
    [[ "${XQ_ENGINE_NETWORK:-}" == /* && -r "$XQ_ENGINE_NETWORK" && -f "$XQ_ENGINE_NETWORK" ]] || {
      printf 'Live checks require XQ_ENGINE_NETWORK pointing to a compatible NNUE file.\n' >&2; exit 2;
    }
    ;;
  *) printf 'Usage: ./verify.sh [--with-engine]\n' >&2; exit 2 ;;
esac
if [[ "$XQ_RUN_ENGINE_TESTS" == 1 ]]; then
  printf 'Verification: offline checks plus explicitly configured local engine checks.\n'
else
  printf 'Verification: offline checks only; actual engine sections report SKIP explicitly. No engine is downloaded or run.\n'
fi

SWIFTC="$(/usr/bin/xcrun --find swiftc)"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
VERIFY_TEMP_DIR="$(/usr/bin/mktemp -d -t xiangqi-verify)"
cleanup_verify_temp() {
  # Never remove an existing project cache, formal app, or user's study data.
  case "$VERIFY_TEMP_DIR" in
    */xiangqi-verify.*)
      [[ -d "$VERIFY_TEMP_DIR" && ! -L "$VERIFY_TEMP_DIR" ]] && /bin/rm -rf -- "$VERIFY_TEMP_DIR"
      ;;
  esac
  return 0
}
trap cleanup_verify_temp EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
/bin/mkdir -p "$VERIFY_TEMP_DIR/bin" "$VERIFY_TEMP_DIR/module-cache" "$VERIFY_TEMP_DIR/tmp" "$VERIFY_TEMP_DIR/test-data"

# macOS Foundation may resolve temporaryDirectory independently of TMPDIR.
# Test-owned stores therefore select this explicit base; TMPDIR is still used
# for compiler/process scratch files. Both are cleaned on this invocation's exit.
export XQ_TEST_TEMP_DIR="$VERIFY_TEMP_DIR/test-data"
export TMPDIR="$VERIFY_TEMP_DIR/tmp/"
export CLANG_MODULE_CACHE_PATH="$VERIFY_TEMP_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$VERIFY_TEMP_DIR/module-cache"
COMPILER_FLAGS=(-target arm64-apple-macosx13.0 -sdk "$SDK_PATH" -module-cache-path "$VERIFY_TEMP_DIR/module-cache")
PASSED_GROUPS=0
compile_and_run() {
  local test_name="$1"
  shift
  "$SWIFTC" "${COMPILER_FLAGS[@]}" "$@" -o "$VERIFY_TEMP_DIR/bin/$test_name"
  "$VERIFY_TEMP_DIR/bin/$test_name"
  PASSED_GROUPS=$((PASSED_GROUPS + 1))
}

compile_and_run rules-tests -swift-version 5 -O Sources/Xiangqi.swift Tests/RulesTests.swift
compile_and_run engine-configuration-tests -swift-version 6 Sources/EngineConfiguration.swift Tests/EngineConfigurationTests.swift
compile_and_run engine-tests -swift-version 6 -D ENGINE_TESTS Sources/EngineConfiguration.swift Sources/PikafishEngine.swift Tests/EngineTests.swift
# All application sources (including GuidedLearningViews) are covered here.
compile_and_run app-tests -swift-version 5 -D APP_TESTS -parse-as-library -Onone \
  -framework SwiftUI -framework AppKit -framework WebKit Sources/*.swift Tests/AppTests.swift
compile_and_run cbl-parser-tests -swift-version 6 -D CBL_PARSER_TESTS \
  Sources/Xiangqi.swift Sources/BookDocument.swift Sources/CBLParser.swift Tests/CBLParserTests.swift
compile_and_run book-learning-guide-tests -swift-version 6 \
  Sources/BookLearningGuide.swift Tests/BookLearningGuideTests.swift
compile_and_run book-study-tests -swift-version 5 -D APP_TESTS -parse-as-library -Onone \
  -framework SwiftUI -framework AppKit -framework WebKit Sources/*.swift Tests/BookStudyTests.swift
compile_and_run book-course-catalog-tests -swift-version 6 -D BOOK_COURSE_TESTS \
  Sources/Xiangqi.swift Sources/BookDocument.swift Sources/CBLParser.swift \
  Sources/BookLearningGuide.swift Sources/BookCourseCatalog.swift Tests/BookCourseCatalogTests.swift
compile_and_run coach-tests -swift-version 6 -D COACH_TESTS \
  Sources/EngineConfiguration.swift Sources/Xiangqi.swift Sources/PikafishEngine.swift Sources/TrainingCoach.swift Tests/CoachTests.swift
compile_and_run opening-content-tests -swift-version 5 -O \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/OpeningCurriculum.swift Tests/OpeningContentTests.swift
compile_and_run practice-content-tests -swift-version 5 -O \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/PracticeCurriculum.swift Tests/PracticeContentTests.swift
compile_and_run systematic-content-tests -swift-version 5 \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/SystematicCurriculum.swift \
  Sources/ProfessionalResources.swift Tests/SystematicContentTests.swift

CORE_SOURCES=(Sources/EngineConfiguration.swift Sources/SafeLocalFile.swift Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/LearningStore.swift Sources/LearningModel.swift
  Sources/ChineseDisplayText.swift Sources/LearningReadingCache.swift Sources/StudyInteractionPresentation.swift
  Sources/OpeningCurriculum.swift Sources/PracticeCurriculum.swift Sources/PikafishEngine.swift Sources/TrainingCoach.swift
  Sources/SystematicCurriculum.swift Sources/ProfessionalResources.swift
  Sources/GuidedLearning.swift Sources/GuidedCurriculum.swift Sources/TextbookCurriculum.swift
  Sources/OpeningRepertoireCurriculum.swift Sources/MiddlegameAtlasCurriculum.swift Sources/EndgameSchoolCurriculum.swift
  Sources/BookCoverage.swift Sources/LibraryCourseCatalog.swift Sources/PWARepositoryData.swift
  Sources/LibraryGeneratedStudy.swift Sources/LibraryLessonBuilder.swift Sources/LibraryCourseLearning.swift
  Sources/PositionLearningInsights.swift Sources/LearningRoadmap.swift Sources/LearningRoadmapContent.swift Sources/LearningJourney.swift
  Sources/LearningRouteNavigation.swift)
compile_and_run book-learning-storage-tests -swift-version 6 -D BOOK_LEARNING_STORAGE_TESTS \
  "${CORE_SOURCES[@]}" Tests/BookLearningStorageTests.swift
compile_and_run import-safety-tests -swift-version 6 -D IMPORT_SAFETY_TESTS \
  "${CORE_SOURCES[@]}" Tests/ImportSafetyTests.swift
compile_and_run book-lesson-tests -swift-version 6 -D BOOK_LESSON_TESTS \
  "${CORE_SOURCES[@]}" Sources/BookDocument.swift Sources/BookLibraryStorage.swift Sources/CBLParser.swift \
  Sources/BookLearningGuide.swift Sources/BookStudyModel.swift Sources/BookCourseCatalog.swift Sources/BookLessonModel.swift \
  Tests/BookLessonTests.swift
# These are required product components, not optional tests. Missing curriculum
# or test files fail verification instead of silently reducing test coverage.
# GuidedLearningViews is separately compiled with all app sources above.
compile_and_run learning-tests -swift-version 6 -D LEARNING_TESTS -D LEARNING_MODEL_TESTS \
  "${CORE_SOURCES[@]}" Tests/LearningTests.swift

compile_and_run guided-learning-tests -swift-version 6 -D GUIDED_TESTS -D GUIDED_MODEL_TESTS \
  "${CORE_SOURCES[@]}" Tests/GuidedLearningTests.swift
compile_and_run textbook-content-tests -swift-version 5 \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/TextbookCurriculum.swift Tests/TextbookContentTests.swift
compile_and_run repertoire-content-tests -swift-version 5 \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/OpeningRepertoireCurriculum.swift Tests/OpeningRepertoireTests.swift
compile_and_run atlas-content-tests -swift-version 5 \
  Sources/SafeLocalFile.swift Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/LearningStore.swift Sources/SystematicCurriculum.swift Sources/MiddlegameAtlasCurriculum.swift \
  Sources/ChineseDisplayText.swift Sources/LibraryCourseCatalog.swift Sources/PWARepositoryData.swift Sources/LibraryGeneratedStudy.swift Sources/LearningRoadmap.swift Tests/MiddlegameAtlasTests.swift
compile_and_run endgame-school-tests -swift-version 5 \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/EndgameSchoolCurriculum.swift Tests/EndgameSchoolTests.swift
compile_and_run book-coverage-tests -swift-version 6 -D BOOK_COVERAGE_TESTS \
  "${CORE_SOURCES[@]}" Tests/BookCoverageTests.swift

# Architecture boundaries added by the 2.0 chessroom rebuild are required gates.
BOARD_SOURCES=(Sources/EngineConfiguration.swift Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/PikafishEngine.swift
  Sources/ChineseDisplayText.swift Sources/BoardMotion.swift Sources/StudioStyle.swift Sources/WarmBoardStyle.swift Sources/BoardView.swift Sources/BoardPreview.swift Sources/PlayUtilities.swift)
compile_and_run warm-style-tests -swift-version 5 -framework SwiftUI -framework AppKit \
  "${BOARD_SOURCES[@]}" Tests/WarmStyleTests.swift
compile_and_run game-record-tests -swift-version 5 -framework SwiftUI -framework AppKit \
  "${BOARD_SOURCES[@]}" Sources/GameRecord.swift Sources/GameModel.swift Sources/PlayUtilitiesViews.swift Sources/ManualRecordViews.swift Tests/GameRecordTests.swift
compile_and_run position-library-tests -swift-version 6 -D POSITION_LIBRARY_TESTS \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/PositionLibrary.swift \
  Sources/PositionLibraryStore.swift Sources/PositionLibraryCurriculumAdapter.swift Tests/PositionLibraryTests.swift
compile_and_run resource-catalog-tests -swift-version 6 -D RESOURCE_CATALOG_TESTS \
  "${CORE_SOURCES[@]}" Sources/ResourceCatalog.swift Tests/ResourceCatalogTests.swift
compile_and_run workspace-integration-tests -swift-version 6 -D WORKSPACE_INTEGRATION_TESTS \
  "${CORE_SOURCES[@]}" Tests/WorkspaceIntegrationTests.swift

# Full repository synchronization and native feature-union gates. No network in
# this script; the explicit --live synchronization is a separate acceptance run.
compile_and_run awesome-resource-index-tests -swift-version 6 -D AWESOME_RESOURCE_INDEX_TESTS \
  Sources/AwesomeResourceIndex.swift Tests/AwesomeResourceIndexTests.swift
compile_and_run pwa-repository-data-tests -swift-version 6 -D PWA_REPOSITORY_DATA_TESTS \
  Sources/Xiangqi.swift Sources/PWARepositoryData.swift Tests/PWARepositoryDataTests.swift
compile_and_run fen-batch-codec-tests -swift-version 6 -D FEN_BATCH_CODEC_TESTS \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/PositionLibrary.swift Sources/FENBatchCodec.swift Tests/FENBatchCodecTests.swift
compile_and_run github-library-sync-tests -swift-version 6 -D GITHUB_LIBRARY_SYNC_TESTS \
  Sources/Xiangqi.swift Sources/AwesomeResourceIndex.swift Sources/PWARepositoryData.swift \
  Sources/SyncedWebResource.swift Sources/GitHubLibrarySync.swift Tests/GitHubLibrarySyncTests.swift
compile_and_run analysis-variation-tests -swift-version 6 \
  Sources/Xiangqi.swift Sources/AnalysisVariation.swift Tests/AnalysisVariationTests.swift
compile_and_run history-rules-tests -swift-version 6 -D GAME_HISTORY_RULES_TESTS \
  Sources/Xiangqi.swift Sources/GameHistoryRules.swift Tests/GameHistoryRulesTests.swift
compile_and_run board-image-import-tests -swift-version 6 -D BOARD_IMAGE_IMPORT_TESTS \
  -framework Vision -framework CoreImage -framework AppKit \
  Sources/Xiangqi.swift Sources/BoardImageImport.swift Tests/BoardImageImportTests.swift
compile_and_run play-utilities-tests -swift-version 5 -framework SwiftUI -framework AppKit \
  "${BOARD_SOURCES[@]}" Sources/GameRecord.swift Sources/GameModel.swift Sources/PlayUtilitiesViews.swift Tests/PlayUtilitiesTests.swift

# All positions are represented in navigation; only a selected position produces
# one bounded reference lesson. Generation/storage tests use isolated fixtures.
compile_and_run library-course-catalog-tests -swift-version 6 -D LIBRARY_COURSE_CATALOG_TESTS \
  Sources/Xiangqi.swift Sources/AwesomeResourceIndex.swift Sources/PWARepositoryData.swift \
  Sources/SyncedWebResource.swift Sources/GitHubLibrarySync.swift Sources/ChineseDisplayText.swift Sources/LibraryCourseCatalog.swift \
  Sources/LibraryCourseCatalogAdapter.swift Tests/LibraryCourseCatalogTests.swift
compile_and_run library-lesson-builder-tests -swift-version 6 -D LIBRARY_LESSON_BUILDER_TESTS \
  Sources/SafeLocalFile.swift Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/LearningStore.swift Sources/PWARepositoryData.swift \
  Sources/EngineConfiguration.swift Sources/PikafishEngine.swift Sources/TrainingCoach.swift Sources/ChineseDisplayText.swift Sources/LibraryCourseCatalog.swift Sources/LibraryGeneratedStudy.swift \
  Sources/LibraryLessonBuilder.swift Sources/PositionLearningInsights.swift Sources/LearningRoadmap.swift Tests/LibraryLessonBuilderTests.swift
compile_and_run library-learning-tests -swift-version 6 -D LIBRARY_LEARNING_TESTS \
  "${CORE_SOURCES[@]}" Tests/LibraryLearningTests.swift

compile_and_run position-learning-insights-tests -swift-version 6 -D POSITION_LEARNING_INSIGHTS_TESTS \
  Sources/Xiangqi.swift Sources/PositionLearningInsights.swift Tests/PositionLearningInsightsTests.swift
compile_and_run learning-journey-tests -swift-version 6 -D LEARNING_JOURNEY_TESTS \
  "${CORE_SOURCES[@]}" Tests/LearningJourneyTests.swift

compile_and_run chinese-display-tests -swift-version 6 -D CHINESE_DISPLAY_TEXT_TESTS \
  Sources/ChineseDisplayText.swift Sources/LibraryCourseCatalog.swift Tests/ChineseDisplayTextTests.swift
compile_and_run learning-reading-cache-tests -swift-version 6 -D LEARNING_READING_CACHE_TESTS \
  "${CORE_SOURCES[@]}" Tests/LearningReadingCacheTests.swift
compile_and_run interaction-refinement-tests -swift-version 6 -D INTERACTION_REFINEMENT_TESTS \
  "${CORE_SOURCES[@]}" Sources/BoardMotion.swift Tests/InteractionRefinementTests.swift

compile_and_run interaction-responsiveness-tests -swift-version 6 -D INTERACTION_RESPONSIVENESS_TESTS \
  "${CORE_SOURCES[@]}" Tests/InteractionResponsivenessTests.swift
compile_and_run study-semantics-tests -swift-version 6 -D STUDY_SEMANTICS_TESTS \
  "${CORE_SOURCES[@]}" Tests/StudySemanticsTests.swift
compile_and_run study-variation-catalog-tests -swift-version 6 -D STUDY_VARIATION_CATALOG_TESTS \
  Sources/Xiangqi.swift Sources/LearningTypes.swift Sources/StudyVariationCatalog.swift Tests/StudyVariationCatalogTests.swift

compile_and_run route-directory-tests -swift-version 6 -D ROUTE_DIRECTORY_TESTS \
  "${CORE_SOURCES[@]}" Tests/RouteDirectoryTests.swift
printf 'PASS: %s verification groups; live-engine lane=%s (review any SKIP lines above).\n' "$PASSED_GROUPS" "$XQ_RUN_ENGINE_TESTS"
