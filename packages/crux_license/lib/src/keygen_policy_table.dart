// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// GENERATED from the suite's SKU catalog -- DO NOT EDIT.
//
// The offline half of licence resolution. A Keygen licence key
// carries a policy id and no entitlements at all, so this table is
// what turns `policy.id` back into a tier and a product set with no
// network round trip. Policies are 1:1 with SKUs, which is what
// makes the mapping total.
//
// Account 58d52938-51ab-4192-85d8-835dfd23fd93, 21 policies.
//
// The generator reconciles the SKU catalog against the live Keygen
// account and refuses to emit if they disagree, so a change here
// starts with a change to the catalog, never with an edit to this
// file.

import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/keygen_policy.dart';
import 'package:crux_license/src/license_tier.dart';

/// Every Keygen policy this build can resolve, keyed by policy id.
///
/// A key whose policy id is absent here is authentic but
/// unresolvable -- almost always a build that predates the SKU. The
/// validator reports that as its own rejection rather than
/// pretending the licence is invalid.
const Map<String, KeygenPolicy> kKeygenPolicies = <String, KeygenPolicy>{
  'd605860a-3fd7-405e-b280-020e8bc0e9a2': KeygenPolicy(
    id: 'd605860a-3fd7-405e-b280-020e8bc0e9a2',
    name: 'wavecrux-pro-monthly',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.waveCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'wavecrux-pro-monthly',
  ),
  'acc0c1df-11b5-464b-bcec-e171a233c601': KeygenPolicy(
    id: 'acc0c1df-11b5-464b-bcec-e171a233c601',
    name: 'wavecrux-pro-annual',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.waveCrux},
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'wavecrux-pro-annual',
  ),
  '372af53a-4181-4fe0-b260-f9e0865ef356': KeygenPolicy(
    id: '372af53a-4181-4fe0-b260-f9e0865ef356',
    name: 'wavecrux-ent-monthly',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{CruxProduct.waveCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'wavecrux-ent-monthly',
  ),
  'fbc21fcb-89a2-412b-a24e-c811f44fc042': KeygenPolicy(
    id: 'fbc21fcb-89a2-412b-a24e-c811f44fc042',
    name: 'wavecrux-ent-annual',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{CruxProduct.waveCrux},
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'wavecrux-ent-annual',
  ),
  'a1442d59-4738-4459-be8c-2a6c94ffeebb': KeygenPolicy(
    id: 'a1442d59-4738-4459-be8c-2a6c94ffeebb',
    name: 'netcrux-pro-monthly',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.netCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'netcrux-pro-monthly',
  ),
  '6c4c2f26-71f7-4166-bd68-f0b98ebc33a4': KeygenPolicy(
    id: '6c4c2f26-71f7-4166-bd68-f0b98ebc33a4',
    name: 'netcrux-pro-annual',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.netCrux},
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'netcrux-pro-annual',
  ),
  'a157dc45-9f46-4bb2-a333-8a9d450ffe1d': KeygenPolicy(
    id: 'a157dc45-9f46-4bb2-a333-8a9d450ffe1d',
    name: 'netcrux-ent-monthly',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{CruxProduct.netCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'netcrux-ent-monthly',
  ),
  '9ab20bd8-0cd1-462f-80ae-6ce723ddb9b5': KeygenPolicy(
    id: '9ab20bd8-0cd1-462f-80ae-6ce723ddb9b5',
    name: 'netcrux-ent-annual',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{CruxProduct.netCrux},
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'netcrux-ent-annual',
  ),
  '9247e8e4-43be-42a4-bd30-2ac6d84f469e': KeygenPolicy(
    id: '9247e8e4-43be-42a4-bd30-2ac6d84f469e',
    name: 'lintcrux-pro-monthly',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.lintCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'lintcrux-pro-monthly',
  ),
  'b4494625-d265-4bcb-8fab-c1baded97ea3': KeygenPolicy(
    id: 'b4494625-d265-4bcb-8fab-c1baded97ea3',
    name: 'lintcrux-pro-annual',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.lintCrux},
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'lintcrux-pro-annual',
  ),
  'c7188c0c-d17d-408a-932c-41a2834c3920': KeygenPolicy(
    id: 'c7188c0c-d17d-408a-932c-41a2834c3920',
    name: 'lintcrux-ent-monthly',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{CruxProduct.lintCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'lintcrux-ent-monthly',
  ),
  'e29d04c0-ecee-4d89-addc-15fd4cdab8dc': KeygenPolicy(
    id: 'e29d04c0-ecee-4d89-addc-15fd4cdab8dc',
    name: 'lintcrux-ent-annual',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{CruxProduct.lintCrux},
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'lintcrux-ent-annual',
  ),
  '416eacca-6f06-4714-8d9f-b3ce78f6eae5': KeygenPolicy(
    id: '416eacca-6f06-4714-8d9f-b3ce78f6eae5',
    name: 'simcrux-pro-monthly',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.simCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'simcrux-pro-monthly',
  ),
  'fff95c60-e89b-4d27-a7c3-dd5f34cec31e': KeygenPolicy(
    id: 'fff95c60-e89b-4d27-a7c3-dd5f34cec31e',
    name: 'simcrux-pro-annual',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.simCrux},
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'simcrux-pro-annual',
  ),
  'f0042fb8-17a1-417f-83f8-9e37597168a6': KeygenPolicy(
    id: 'f0042fb8-17a1-417f-83f8-9e37597168a6',
    name: 'simcrux-ent-monthly',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{CruxProduct.simCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'simcrux-ent-monthly',
  ),
  '997e030e-2e88-42aa-88d5-e313267437fe': KeygenPolicy(
    id: '997e030e-2e88-42aa-88d5-e313267437fe',
    name: 'simcrux-ent-annual',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{CruxProduct.simCrux},
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'simcrux-ent-annual',
  ),
  'a4af38e8-417a-43c3-8191-66807ee7ff7c': KeygenPolicy(
    id: 'a4af38e8-417a-43c3-8191-66807ee7ff7c',
    name: 'suite-pro-monthly',
    tier: LicenseTier.pro,
    products: <CruxProduct>{
      CruxProduct.waveCrux,
      CruxProduct.netCrux,
      CruxProduct.lintCrux,
      CruxProduct.simCrux,
    },
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'suite-pro-monthly',
  ),
  '1efa72c0-b310-48eb-a72c-dda64820f9da': KeygenPolicy(
    id: '1efa72c0-b310-48eb-a72c-dda64820f9da',
    name: 'suite-pro-annual',
    tier: LicenseTier.pro,
    products: <CruxProduct>{
      CruxProduct.waveCrux,
      CruxProduct.netCrux,
      CruxProduct.lintCrux,
      CruxProduct.simCrux,
    },
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'suite-pro-annual',
  ),
  '2e44ce1d-b74a-4b22-8339-289d2b25d520': KeygenPolicy(
    id: '2e44ce1d-b74a-4b22-8339-289d2b25d520',
    name: 'suite-ent-monthly',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{
      CruxProduct.waveCrux,
      CruxProduct.netCrux,
      CruxProduct.lintCrux,
      CruxProduct.simCrux,
    },
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'suite-ent-monthly',
  ),
  '0c0dfcf4-d62a-4b23-aa41-d54f13ce25e5': KeygenPolicy(
    id: '0c0dfcf4-d62a-4b23-aa41-d54f13ce25e5',
    name: 'suite-ent-annual',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{
      CruxProduct.waveCrux,
      CruxProduct.netCrux,
      CruxProduct.lintCrux,
      CruxProduct.simCrux,
    },
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'suite-ent-annual',
  ),
  '3385bb71-4305-4ccb-b389-5339492fa2ee': KeygenPolicy(
    id: '3385bb71-4305-4ccb-b389-5339492fa2ee',
    name: 'edu-annual',
    tier: LicenseTier.edu,
    products: <CruxProduct>{
      CruxProduct.waveCrux,
      CruxProduct.netCrux,
      CruxProduct.lintCrux,
      CruxProduct.simCrux,
    },
    duration: Duration(seconds: 31622400),
  ),
};
