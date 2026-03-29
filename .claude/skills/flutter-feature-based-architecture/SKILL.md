---
name: "flutter-feature-based-architecture"
description: "Architects a Flutter application using a Feature-Based structure with Riverpod state management and a shared core layer. Use when structuring a new project, adding features, or refactoring for scalability."
metadata:
  model: "models/gemini-3.1-pro-preview"
  last_modified: "Fri, 28 Mar 2026 04:05:00 GMT"
---

# Flutter Feature-Based Architecture with Riverpod

## Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Core (Global) Layer](#core-global-layer)
- [Feature Layer](#feature-layer)
- [State Management with Riverpod](#state-management-with-riverpod)
- [Feature Implementation Workflow](#feature-implementation-workflow)
- [Naming Conventions](#naming-conventions)
- [Examples](#examples)

## Overview

This skill enforces a **Feature-Based Architecture** where code is organized by feature (vertical slices) rather than by technical layer. Shared, cross-cutting concerns live in a `core/` directory. State management is handled exclusively with **Riverpod** (`flutter_riverpod` / `hooks_riverpod`).

### Core Principles

- **Feature Isolation:** Each feature owns its data, providers, and views. Features must **never** import from other features. If two features need the same code, move it to `core/`.
- **Riverpod-First State Management:** All state is managed via Riverpod providers. No `ChangeNotifier`, `Bloc`, or raw `setState` for business logic.
- **Core for Shared Code:** Anything used by 2+ features belongs in `core/`. This includes shared models, repositories, providers, components, constants, utilities, and infrastructure.
- **Unidirectional Data Flow:** Data flows from Repository → Provider/StateNotifier → View. User events flow from View → Provider/StateNotifier → Repository.
- **Single Source of Truth (SSOT):** Each piece of data has exactly one authoritative source — the Repository. Providers expose that data reactively to the UI.

## Project Structure

```
lib/
├── core/                          # Shared, cross-cutting concerns (global)
│   ├── components/                # Reusable UI widgets used across features
│   ├── constants/                 # App-wide constants (colors, URLs, config)
│   ├── extensions/                # Dart extension methods on common types
│   ├── locales/                   # Localization keys and config
│   ├── logger/                    # App-wide logging utility
│   ├── models/                    # Shared domain models
│   ├── providers/                 # Shared Riverpod providers
│   ├── repository/                # Shared repositories & services
│   ├── routes/                    # App routing / navigation config
│   ├── theme/                     # App theme data (colors, text styles, etc.)
│   └── utils/                     # General-purpose utility functions
│
├── features/                      # Feature modules (vertical slices)
│   ├── auth/                      # Example feature
│   │   ├── data/
│   │   │   ├── models/
│   │   │   └── repository/
│   │   ├── providers/
│   │   └── views/
│   │       └── components/
│   ├── home/                      # Example feature
│   ├── settings/                  # Example feature
│   └── ...
│
└── main.dart                      # App entry point
```

## Core (Global) Layer

The `core/` directory holds code that is **shared across multiple features**. The rule is simple: *if it's used by 2+ features, it belongs in `core/`*.

### `core/constants/`

App-wide constant values. Use a barrel file (`constants.dart`) to re-export all files.

| What to put here | Example |
|-----------------|---------|
| Color constants | `AppColors` with static `Color` fields (primary, secondary, error, success, etc.) |
| URL constants | `AppUrls` with static URL strings (API base, privacy policy, CDN paths) |
| Size/spacing constants | `AppSizes` with static doubles for padding, radius, etc. |
| Config values | API keys (non-secret), pagination limits, timeout durations |

### `core/components/`

Reusable UI widgets consumed by multiple features. These are **presentational** widgets that receive data via constructor params — they should not contain business logic.

Examples: custom dropdowns, reusable form fields, loading indicators, empty state widgets, confirmation dialogs.

### `core/extensions/`

Dart extension methods on common types (`String`, `DateTime`, `BuildContext`, `Color`, etc.) that are used across the app.

### `core/locales/`

Localization configuration and generated key files (e.g., for `easy_localization`, `intl`, or `flutter_localizations`).

### `core/logger/`

A singleton logging utility wrapping a logging package (e.g., `logger`). Provides static methods like `Log.debug()`, `Log.info()`, `Log.error()`, `Log.warning()`. Should be debug-only in release builds.

### `core/models/`

Domain models shared across features. Use a barrel file (`models.dart`) for re-exports. Only place models here if they are truly cross-feature. Feature-specific models stay in their feature's `data/models/`.

### `core/providers/`

Riverpod providers that are consumed by multiple features. Typically these wrap shared repositories or expose shared state (e.g., current user, app settings, connectivity).

### `core/repository/`

Repositories and services for shared data domains. Organize by subdomain:

```
core/repository/
├── api/                # Base API client, HTTP wrapper
├── auth/               # Shared auth repository (if used by multiple features)
├── storage/            # Local storage / secure storage wrapper
└── ...
```

Each repository file should also declare its own Riverpod `Provider` at the bottom of the file.

### `core/routes/`

App-level routing and navigation configuration (e.g., `GoRouter` setup, route constants, route guards).

### `core/theme/`

App theme data — `ThemeData`, text styles, component themes. Keep color definitions in `constants/` and reference them here.

### `core/utils/`

General-purpose utility classes and functions that don't fit elsewhere. Examples: phone/URL launchers, file helpers, crypto utilities, date formatters, Excel/CSV export helpers.

## Feature Layer

Each feature directory under `features/` follows a **consistent internal structure** with 3 primary subdirectories:

```
features/<feature_name>/
├── data/                    # Data layer
│   ├── models/              #   Domain models specific to this feature
│   │   ├── <model>.dart
│   │   └── models.dart      #   Barrel file (optional)
│   └── repository/          #   Repositories (Firestore CRUD, API calls, etc.)
│       └── <feature>_repository.dart
│
├── providers/               # State management layer
│   └── <feature>_providers.dart   # All Riverpod providers for this feature
│
└── views/                   # UI layer
    ├── <feature>_page.dart         # Main page widget(s)
    ├── add_<feature>_page.dart     # Create/edit page (if applicable)
    └── components/                 # Feature-specific UI components
        └── <component>.dart
```

### Optional Subdirectories

A feature may add extra subdirectories when needed:

| Directory | When to add |
|-----------|-------------|
| `utils/` | Feature has its own utility/helper functions |
| `services/` | Feature needs stateless service classes (e.g., scheduling logic, data transformation) |

### Rules

1. **Never import from another feature.** If feature A needs something from feature B, extract it to `core/`.
2. **Keep views lean.** Views (`ConsumerWidget` / `ConsumerStatefulWidget`) should only handle UI concerns — layout, animations, navigation. All business logic lives in providers/StateNotifiers.
3. **One provider file per feature** is the default. Split into multiple files only when the file exceeds ~400 lines.
4. **Models must have serialization.** Every model needs `fromMap()` / `fromJson()` and `toMap()` / `toJson()` along with `copyWith()`.

## State Management with Riverpod

### Provider Types

| Provider Type | When to Use | Example |
|---------------|-------------|---------|
| `Provider` | Expose a stateless repository or service instance | `final repoProvider = Provider<Repo>((ref) => Repo());` |
| `StateProvider` | Simple mutable state (filters, toggles, search query) | `final searchProvider = StateProvider<String>((ref) => '');` |
| `StateNotifierProvider` | Complex state with methods (CRUD controllers, paginated lists) | `final listProvider = StateNotifierProvider<Notifier, State>((ref) { ... });` |
| `FutureProvider` | One-shot async data fetching | `final dataProvider = FutureProvider<List<Item>>((ref) async { ... });` |
| `FutureProvider.family` | Parameterized async data fetching | `final itemProvider = FutureProvider.family<Item?, String>((ref, id) async { ... });` |
| `StreamProvider` | Real-time data streams (Firestore snapshots, WebSocket) | `final streamProvider = StreamProvider<List<Item>>((ref) { ... });` |

### Provider File Organization

Each feature's `providers/` file should be organized in this order:

1. **Repository Providers** — `Provider<XRepository>`
2. **Filter/UI State Providers** — `StateProvider<String>`, `StateProvider<bool>`
3. **State Classes** — Immutable state objects with `copyWith()`
4. **StateNotifier Classes** — Business logic (list pagination, CRUD operations)
5. **StateNotifierProvider declarations** — Wiring notifiers to their dependencies

### Use `autoDispose` by default

Prefer `.autoDispose` on providers that are scoped to a screen or feature:

```dart
final featureListProvider = StateNotifierProvider.autoDispose<
  FeatureListNotifier, FeatureListState
>((ref) { ... });
```

This ensures state is cleaned up when the user navigates away.

## Feature Implementation Workflow

Follow this sequential workflow when adding a new feature:

**Task Progress:**

- [ ] **Step 1: Create Feature Directory.** Create `lib/features/<feature_name>/` with subdirectories: `data/models/`, `data/repository/`, `providers/`, `views/`, and optionally `views/components/`.
- [ ] **Step 2: Define Domain Models.** Create model classes in `data/models/` with `fromMap()`, `toMap()`, and `copyWith()` methods.
- [ ] **Step 3: Implement Repository.** Create repository class in `data/repository/` for data operations (API calls, database CRUD, etc.).
- [ ] **Step 4: Implement Providers.** Create `providers/<feature>_providers.dart` with:
  - Repository `Provider`
  - Filter `StateProvider`s (if needed)
  - State class + `StateNotifier` + `StateNotifierProvider` for list/pagination
  - State class + `StateNotifier` + `StateNotifierProvider` for CRUD controller
- [ ] **Step 5: Implement Views.** Create pages in `views/` as `ConsumerWidget` or `ConsumerStatefulWidget`. Use `ref.watch()` for reactive state, `ref.read()` for one-shot actions.
- [ ] **Step 6: Extract Shared Code.** If any model, provider, component, or utility is needed by another feature, move it to the appropriate `core/` subdirectory.
- [ ] **Step 7: Wire Navigation.** Add the new feature's routes to `core/routes/` and any navigation entry points.

## Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Feature directory | `snake_case` | `user_profile/`, `order_history/` |
| Model files | `snake_case` | `user_model.dart`, `order_item.dart` |
| Repository files | `<feature>_repository.dart` | `auth_repository.dart` |
| Provider files | `<feature>_providers.dart` | `auth_providers.dart` |
| View files | `<feature>_page.dart` | `auth_page.dart`, `login_page.dart` |
| StateNotifier classes | `PascalCase` + `Notifier` or `Controller` | `OrderListNotifier`, `AuthController` |
| State classes | `PascalCase` + `State` | `OrderListState`, `AuthState` |
| Provider variables | `camelCase` + `Provider` | `orderListProvider`, `authRepositoryProvider` |
| Barrel exports | `models.dart`, `constants.dart` | Re-export all files in the directory |

## Examples

### Data Layer: Model

```dart
// features/orders/data/models/order_model.dart
class OrderModel {
  final String id;
  final String customerName;
  final double total;
  final DateTime createdAt;

  const OrderModel({
    required this.id,
    required this.customerName,
    required this.total,
    required this.createdAt,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'] ?? '',
      customerName: map['customerName'] ?? '',
      total: (map['total'] ?? 0).toDouble(),
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'customerName': customerName,
    'total': total,
    'createdAt': createdAt.toIso8601String(),
  };

  OrderModel copyWith({
    String? id,
    String? customerName,
    double? total,
    DateTime? createdAt,
  }) {
    return OrderModel(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      total: total ?? this.total,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
```

### Data Layer: Repository

```dart
// features/orders/data/repository/order_repository.dart
class OrderRepository {
  // Inject or instantiate your data source (Firestore, REST API, etc.)

  Future<String> addOrder(OrderModel order) async { /* ... */ }
  Future<void> updateOrder(String id, OrderModel order) async { /* ... */ }
  Future<void> deleteOrder(String id) async { /* ... */ }
  Future<OrderModel?> getOrderById(String id) async { /* ... */ }

  // Paginated fetch returning items + cursor for next page
  Future<Map<String, dynamic>> getOrdersPaginated(
    dynamic lastCursor, {
    int limit = 10,
    String? searchQuery,
  }) async { /* ... */ }
}
```

### Provider Layer: Paginated List

```dart
// features/orders/providers/order_providers.dart

// 1. Repository Provider
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository();
});

// 2. Filter Providers
final orderSearchQueryProvider = StateProvider<String>((ref) => '');

// 3. List State
class OrderListState {
  final List<OrderModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final bool hasMore;
  final dynamic lastCursor;

  const OrderListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.hasMore = true,
    this.lastCursor,
  });

  OrderListState copyWith({ /* all fields */ });
}

// 4. List Notifier
class OrderListNotifier extends StateNotifier<OrderListState> {
  final OrderRepository _repository;
  final Ref _ref;
  final int _pageSize = 10;

  OrderListNotifier(this._repository, this._ref)
    : super(const OrderListState()) {
    fetchFirstPage();
  }

  Future<void> fetchFirstPage() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.getOrdersPaginated(
        null,
        limit: _pageSize,
        searchQuery: _ref.read(orderSearchQueryProvider),
      );
      final List<OrderModel> items = result['items'];
      state = state.copyWith(
        items: items,
        isLoading: false,
        lastCursor: result['lastCursor'],
        hasMore: items.length >= _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final result = await _repository.getOrdersPaginated(
        state.lastCursor,
        limit: _pageSize,
        searchQuery: _ref.read(orderSearchQueryProvider),
      );
      final List<OrderModel> newItems = result['items'];
      state = state.copyWith(
        items: [...state.items, ...newItems],
        isLoadingMore: false,
        lastCursor: result['lastCursor'],
        hasMore: newItems.length >= _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void refresh() => fetchFirstPage();
}

// 5. List Provider (autoDispose)
final orderListProvider = StateNotifierProvider.autoDispose<
  OrderListNotifier, OrderListState
>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  ref.watch(orderSearchQueryProvider); // re-create on filter change
  return OrderListNotifier(repository, ref);
});
```

### Provider Layer: CRUD Controller

```dart
// (continued in the same providers file)

class OrderControllerState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;

  const OrderControllerState({
    this.isLoading = false,
    this.error,
    this.isSuccess = false,
  });

  OrderControllerState copyWith({ /* all fields */ });
}

class OrderController extends StateNotifier<OrderControllerState> {
  final OrderRepository _repository;
  final Ref _ref;

  OrderController(this._repository, this._ref)
    : super(const OrderControllerState());

  Future<void> addOrder(OrderModel order) async {
    state = const OrderControllerState(isLoading: true);
    try {
      await _repository.addOrder(order);
      state = const OrderControllerState(isSuccess: true);
      _ref.read(orderListProvider.notifier).refresh();
    } catch (e) {
      state = OrderControllerState(error: e.toString());
    }
  }

  Future<void> deleteOrder(String id) async {
    state = const OrderControllerState(isLoading: true);
    try {
      await _repository.deleteOrder(id);
      state = const OrderControllerState(isSuccess: true);
      _ref.read(orderListProvider.notifier).refresh();
    } catch (e) {
      state = OrderControllerState(error: e.toString());
    }
  }
}

final orderControllerProvider = StateNotifierProvider.autoDispose<
  OrderController, OrderControllerState
>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return OrderController(repository, ref);
});
```

### UI Layer: ConsumerWidget View

```dart
// features/orders/views/order_list_page.dart
class OrderListPage extends ConsumerWidget {
  const OrderListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listState = ref.watch(orderListProvider);

    if (listState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (listState.error != null) {
      return Center(child: Text('Error: ${listState.error}'));
    }

    return ListView.builder(
      itemCount: listState.items.length + (listState.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == listState.items.length) {
          // Load more trigger
          ref.read(orderListProvider.notifier).fetchNextPage();
          return const Center(child: CircularProgressIndicator());
        }
        final order = listState.items[index];
        return ListTile(
          title: Text(order.customerName),
          subtitle: Text('\$${order.total.toStringAsFixed(2)}'),
        );
      },
    );
  }
}
```

### Core Layer: Shared Component

```dart
// core/components/search_field.dart
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search...',
  });

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}
```
