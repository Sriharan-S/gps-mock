import 'package:flutter_test/flutter_test.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> stateWithFavorites(int count) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    for (var i = 0; i < count; i++) {
      state.updateLocation(LatLng(10.0 + i, 20.0), address: 'Place $i');
      await state.addFavorite('Favorite $i');
      // Ids come from the clock; keep them distinct.
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    return state;
  }

  test('unassigned tiles follow the first favorites, including new ones',
      () async {
    final state = await stateWithFavorites(2);
    expect(state.favoriteOnTile(0)?.name, 'Favorite 0');
    expect(state.favoriteOnTile(2), isNull);

    state.updateLocation(const LatLng(1, 1), address: 'Later');
    await state.addFavorite('Favorite 2');
    expect(state.favoriteOnTile(2)?.name, 'Favorite 2');
  });

  test('assigning moves a favorite to exactly one tile', () async {
    final state = await stateWithFavorites(5);
    final fifth = state.favorites[4];
    expect(state.tileSlotOf(fifth), isNull);

    await state.assignTile(fifth, 0);
    expect(state.tileSlotOf(fifth), 0);
    expect(state.favoriteOnTile(0)?.id, fifth.id);
    // The other tiles keep what they showed.
    expect(state.favoriteOnTile(1)?.name, 'Favorite 1');

    await state.assignTile(fifth, 3);
    expect(state.tileSlotOf(fifth), 3);
    expect(state.favoriteOnTile(0), isNull);

    await state.assignTile(fifth, null);
    expect(state.tileSlotOf(fifth), isNull);
  });

  test('a deleted favorite leaves its tile empty', () async {
    final state = await stateWithFavorites(3);
    final first = state.favorites.first;
    await state.assignTile(first, 0);
    await state.removeFavorite(first);
    expect(state.favoriteOnTile(0), isNull);
  });
}
