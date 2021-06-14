import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geo_firestore_flutter/src/geo_hash_query.dart';
import 'package:geo_firestore_flutter/src/geo_hash.dart';
import 'package:geo_firestore_flutter/src/geo_utils.dart';

///
/// A GeoFirestore instance is used to store and query geo location data in Firestore.
///
class GeoFirestore {
  late CollectionReference<Map<String, dynamic>> collectionReference;

  GeoFirestore(CollectionReference<Map<String, dynamic>> collectionReference) {
    this.collectionReference = collectionReference;
  }

  ///
  /// Build a GeoPoint from a [documentSnapshot]
  ///
  static GeoPoint? getLocationValue(DocumentSnapshot documentSnapshot) {
    try {
      final data = documentSnapshot.data() as Map<String, dynamic>;
      if (data != null && data['l'] != null) {
        final location = data['l'];
        final latitude = location[0];
        final longitude = location[1];
        if (GeoUtils.coordinatesValid(latitude, longitude)) {
          return location;
        }
      }
      return null;
    } catch (e) {
      print('Error occurred when getLocationValue: ' + e.toString());
      return null;
    }
  }

  /// Sets the [location] of a document for the given [documentID].
  Future<dynamic> setLocation(String documentID, GeoPoint location) async {
    var docRef = this.collectionReference.doc(documentID);
    var geoHash = GeoHash.encode(location.latitude, location.longitude);
    // Create a Map with the fields to add
    var updates = Map<String, dynamic>();
    updates['g'] = geoHash;
    updates['l'] = [location.latitude, location.longitude];
    // Update the DocumentReference with the location data
    return await docRef.set(updates, SetOptions(merge: true));
  }

  ///
  /// Removes the [location] of a document for the given [documentID].
  ///
  Future<dynamic> removeLocation(String documentID, GeoPoint location) async {
    //Get the DocumentReference for this documentID
    var docRef = this.collectionReference.doc(documentID);
    //Create a Map with the fields to add
    var updates = Map<String, dynamic>();
    updates['g'] = null;
    updates['l'] = null;
    //Update the DocumentReference with the location data
    await docRef.set(updates, SetOptions(merge: true));
  }

  ///
  /// Gets the current location of a document for the given [documentID].
  ///
  Future<GeoPoint?> getLocation(String documentID) async {
    final snapshot = await this.collectionReference.doc(documentID).get();
    final geoPoint = getLocationValue(snapshot);
    return geoPoint;
  }

  ///
  /// Returns the documents centered at a given location and with the given radius.
  /// [center]      The center of the query
  /// [radius]      The radius of the query, in kilometers. The maximum radius that is
  ///               supported is about 8587km. If a radius bigger than this is passed we'll cap it.
  /// [addDistance] Whether to process data and add distance property to returned documents, defaults to True.
  /// [exact]       Whether to process data and remove documents that are further than specified radius, defaults to True.
  ///
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> getAtLocation(
    GeoPoint center,
    double radius, {
    bool exact = true,
    bool addDistance = true,
  }) async {
    // Get the futures from Firebase Queries generated from GeoHashQueries
    final futures = GeoHashQuery.queriesAtLocation(
            center, GeoUtils.capRadius(radius) * 1000)
        .map((query) => query.createFirestoreQuery(this).get());

    // Await the completion of all the futures
    try {
      List<DocumentSnapshot<Map<String, dynamic>>> documents = [];
      final snapshots = await Future.wait(futures);
      snapshots.forEach((snapshot) {
        snapshot.docs.forEach((doc) {
          if (addDistance || exact) {
            final latLng = doc.data()['l'];
            final distance = GeoUtils.distance(center, GeoPoint(latLng[0], latLng[1]));
            if (exact) {
              if (distance <= radius) {
                doc.data()['distance'] = distance;
                documents.add(doc);
              }
            } else {
              doc.data()['distance'] = distance;
              documents.add(doc);
            }
          } else {
            documents.add(doc);
          }
        });
      });
      return documents;
    } catch (e) {
      print('Failed retrieving data for geo query: ' + e.toString());
      throw e;
    }
  }
}
