// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// GENERATED FILE — DO NOT EDIT BY HAND.
//
// The lint waivers below are properties of the source text, not of this
// generator: a legal document has paragraphs longer than 80 columns and
// apostrophes inside them, and reflowing or re-quoting either one would be
// editing the agreement to suit a style rule.
// ignore_for_file: lines_longer_than_80_chars, avoid_escaping_inner_quotes
// Regenerate with `tool/generate-eula-document.py`, passing the markdown the
// agreement is maintained in. Editing this file directly puts the agreement the
// applications present out of step with the one counsel finalised — which is
// the single failure this generator exists to prevent. The published text is at
// https://edacrux.app/eula.

import 'package:meta/meta.dart';

/// One block of the agreement: a section heading, or a paragraph under one.
///
/// The document is carried as blocks rather than as one string so the dialog
/// can style headings without parsing prose at build time, and so a test can
/// assert the presence of a numbered section rather than a substring.
@immutable
class CruxEulaBlock {
  /// Creates a block.
  const CruxEulaBlock({required this.isHeading, required this.text});

  /// Whether this block is a section heading.
  final bool isHeading;

  /// The block's text, with markdown emphasis removed.
  final String text;
}

/// The version of the agreement compiled into this build.
///
/// **This is the acceptance key.** `CruxEulaAcceptanceStore` persists the
/// version the user accepted rather than a boolean, because EULA section 2.3
/// requires active re-acceptance when the agreement changes substantively and
/// a boolean cannot express "accepted an older one". Raising this constant is
/// therefore what re-prompts every installation; never raise it for a
/// typographical fix.
const String kCruxEulaVersion = '1.0';

/// The effective date printed in the dialog's header, as counsel set it.
const String kCruxEulaEffectiveDate = 'October 1, 2026';

/// The agreement itself, in document order.
const List<CruxEulaBlock> kCruxEulaDocument = <CruxEulaBlock>[
  CruxEulaBlock(
    isHeading: false,
    text: 'A supplement to the Website and Software Terms of Use',
  ),
  CruxEulaBlock(
    isHeading: false,
    text: 'Effective Date: October 1, 2026 · Version 1.0',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'This EDACrux End User License Agreement (this "EULA") supplements, and is incorporated into, the Website and Software Terms of Use available at edacrux.app/terms (the "Terms"), between Ferrite Engineering LLC, a Colorado limited liability company ("Ferrite," "we," "us," or "our"), and the individual or entity that downloads, installs, activates, or uses any Application (the "Licensee," "you," or "your"). Capitalized terms not defined here have the meanings given in the Terms.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'This EULA governs every edition of every Application: Open Core, Educational, Pro, and Enterprise. Where this EULA conflicts with the Terms, this EULA controls as to the Applications; the Terms otherwise continue to apply in full, including Section 11 (No Professional Advice), Section 12 (Export Control and Sanctions Compliance), Sections 18 through 21 (Warranty, Liability, Indemnification, and Governing Law), and the Privacy Policy incorporated there by reference.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Order of precedence: (1) a signed Enterprise Order Form referencing this EULA, if any; (2) this EULA; (3) the Terms. An Open-Source Component\'s own license controls over all three as to that component (Section 3).',
  ),
  CruxEulaBlock(isHeading: true, text: '1. Definitions'),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"Application" means any of the four EDACrux applications: WaveCrux (waveform viewer), NetCrux (RTL schematic browser), LintCrux (lint dashboard), and SimCrux (regression manager); and "Applications" means all of them. The Applications are collectively marketed as the EDACrux suite.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"Authorized User" means an individual employee, contractor, student, or agent of Licensee to whom Licensee assigns a Seat.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"Edition" means one of the four feature tiers of an Application: Open Core, Educational ("EDU"), Pro, or Enterprise.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"License Key" means the signed credential, license file, or offline activation token issued by or on behalf of Ferrite that unlocks the Educational, Pro, or Enterprise Edition.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"Open-Source Component" means any component of an Application that Ferrite or a third party makes available under an open-source license, including the Apache License 2.0.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"Order Form" means a signed or accepted quote, invoice, or ordering document that references this EULA.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"Seat" means a single named Authorized User (Educational and Pro) or a single entitlement counted toward Licensee\'s purchased seat count (Enterprise).',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"Telemetry" means the anonymous usage measurement described in Section 8 and in the Privacy Policy.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '"Update Check" means the periodic network request by which an Application checks whether a newer build is available.',
  ),
  CruxEulaBlock(isHeading: true, text: '2. Acceptance'),
  CruxEulaBlock(
    isHeading: false,
    text:
        '2.1 In-application acceptance. Each Application presents this EULA on first launch and does not proceed until you accept it. You accept this EULA by any of: (a) indicating acceptance in the Application; (b) activating a License Key; or (c) installing or using an Application.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '2.2 Authority. If you accept on behalf of a company, university, laboratory, or other entity, you represent that you are authorized to bind that entity, and "you" means both you individually and that entity.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '2.3 Changes. Ferrite may update this EULA for future releases. A change applies to a release you install after the change takes effect; it does not retroactively alter the terms of a release you have already installed. Material changes will be identified in the release notes and on the Site, and the Application will present the updated EULA for acceptance.',
  ),
  CruxEulaBlock(isHeading: true, text: '3. Open-Source Components'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Nothing in this EULA restricts, limits, or is intended to override any right granted to you under an Open-Source Component\'s own license. Where Ferrite makes an Application\'s source code available under the Apache License 2.0 or another open-source license, that license governs your rights in that source code and in binaries built from it, and this EULA applies to that Application only as to (a) components Ferrite does not release under an open-source license, (b) Ferrite\'s trademarks and branding, and (c) the services described in Sections 7 through 9, which Ferrite operates and which no open-source license addresses.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Ferrite identifies which components are Open-Source Components at the time of download or in the accompanying documentation.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Nothing in this Section 3, and no in-application dialog presented under Section 2.1, conditions any right you have under an Open-Source Component\'s license on accepting this EULA. The source code Ferrite releases under the Apache License 2.0 or another open-source license remains available on the same terms at Ferrite\'s public source repository, whether or not this EULA is presented to you or accepted by you.',
  ),
  CruxEulaBlock(isHeading: true, text: '4. License Grants'),
  CruxEulaBlock(
    isHeading: false,
    text:
        '4.1 Open Core Edition. Ferrite grants you a worldwide, royalty-free, non-exclusive, non-transferable license to install and use the Open Core Edition of any Application, on any number of devices, for any purpose, including commercial use, subject to this EULA and the Terms. No fee, license key, registration, or account is required. The Open Core Edition is a complete product, not a time-limited trial.',
  ),
  CruxEulaBlock(isHeading: false, text: '4.2 Educational Edition.'),
  CruxEulaBlock(
    isHeading: false,
    text:
        '(a) Grant. Ferrite grants you a personal, non-exclusive, non-transferable, non-sublicensable license to install and use the Educational Edition of the Applications for the term of your Educational License.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '(b) NON-COMMERCIAL USE ONLY. The Educational Edition is licensed solely for non-commercial purposes: coursework, teaching, academic research, personal study, and personal learning projects. You may not use the Educational Edition for any commercial purpose, including: work performed for or on behalf of an employer or client; work performed in the course of employment, consulting, or contracting; work on a product, service, or design that is sold, licensed, or offered commercially; work funded by a commercial sponsor where the sponsor obtains rights in the results; or work performed by or for a commercial entity. For the avoidance of doubt, an internship, co-op, or similar placement with a commercial entity is work performed by or for a commercial entity, whether or not it is paid and whether or not it is done for academic credit. Academic research funded by a government or nonprofit grant, and published for academic purposes, is not commercial use for this purpose. If your use is or becomes commercial, you must obtain a Pro or Enterprise License.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '(c) Eligibility and re-verification. The Educational Edition is available to students, educators, and academic researchers. Ferrite issues an Educational License after verifying an institutional email address. The license has a term of one year and requires re-verification of that address to renew. Ferrite may require reasonable additional evidence of eligibility, and may decline or revoke an Educational License where eligibility is not established.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '(d) Feature scope. The Educational Edition unlocks the same features as the Pro Edition. The distinction between them is in these license terms, not in functionality.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '4.3 Pro Edition. Subject to payment of the applicable fees, Ferrite grants you a limited, non-exclusive, non-transferable, non-sublicensable license to install and use the Pro Edition of the Applications covered by your License Key, for your own commercial or non-commercial engineering work, as a single Authorized User, on the number of devices permitted by your License Key.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '4.4 Enterprise Edition. Subject to the applicable Order Form, Ferrite grants Licensee a limited, non-exclusive, non-transferable, non-sublicensable license to install and use the Enterprise Edition of the Applications covered by the Order Form for Licensee\'s own internal engineering work, on the number of Seats purchased. Licensee may assign and reassign Seats among Authorized Users, provided a Seat is not used concurrently by more than one Authorized User except as expressly permitted by a concurrent-use Order Form.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '4.5 One key, whole purchase. Ferrite issues a single License Key per customer regardless of how many Applications are purchased. A key identifies the Applications and the Edition it unlocks; a suite key unlocks all four. The same key is entered into each Application. Licensee is responsible for distributing and safeguarding its key and for any use of it, authorized or not, by a person who obtains it through Licensee.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '4.6 Edition scope. Each grant extends only to the feature set that the Site or the applicable Order Form identifies, at the time of purchase, as included in that Edition. A feature identified as "Planned" is not part of the license granted until Ferrite makes it generally available.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '4.7 Reservation of rights. The Applications are licensed, not sold. Section 5.2 of the Terms applies. No rights are granted other than as expressly set out in this EULA, the Terms, and any applicable open-source license.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '4.8 Your work is yours. Ferrite claims no ownership of the design files, waveforms, netlists, reports, sessions, or other materials you create or process using the Applications. Section 5.3 of the Terms applies to all Editions.',
  ),
  CruxEulaBlock(
    isHeading: true,
    text: '5. License Keys, Activation, and Offline Operation',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '5.1 Local verification. A License Key is verified on your device, using a public key compiled into the Application. Verification requires no network connection and no contact with Ferrite or any third party. This is a deliberate design property: an Application with a valid key runs fully offline, including on an air-gapped network.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '5.2 Machine activation. When a network is available, the Application may register the device against your license with our licensing provider so that Seats can be counted, and may periodically confirm that the license has not expired, been renewed, or been revoked. This exchange transmits your License Key, a randomly generated installation identifier, a device name, and a platform name. It transmits none of your design data. See the Privacy Policy.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '5.3 Failure to reach the licensing service is never a denial of service. If the licensing service cannot be reached, the Application continues to run at the Edition your key grants. Ferrite does not treat "we could not check" as "you are not licensed."',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '5.4 Grace periods. If a license actually expires or is actually revoked, the Application continues to operate at its licensed Edition for a grace period measured from expiry: 30 days for Pro, 60 days for Educational, and 90 days for Enterprise. The Application displays a notice during the grace period. After the grace period, the Application reverts to the Open Core Edition as described in Section 10.4.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'A missed or failed attempt to reach the licensing service under Section 5.2 does not, by itself, start a grace period or cause a reversion to the Open Core Edition; Section 5.3 governs that situation. A device that is never connected to a network, including a device activated under Section 5.5, is not subject to a grace period and continues to operate at its licensed Edition for the full term of the license.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '5.5 Offline and air-gapped activation. For a device with no network access, the Application can export a request identifying that device, which Ferrite (or, for Enterprise, Licensee\'s administrator) can exchange for a license file that the Application imports and verifies locally. The exported request contains no credential and no design data.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '5.6 Deactivation. You may release a device\'s Seat from within the Application. Ferrite may require a Seat to be released before it can be reassigned.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '5.7 No circumvention. You will not circumvent, disable, or tamper with license verification, activation, seat counting, or any other technical protection measure in the Applications, nor use a License Key outside the scope of the Edition and seat count it grants.',
  ),
  CruxEulaBlock(isHeading: true, text: '6. Cross-Product Interoperability'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'The Applications can exchange messages with one another on the same machine, for example, to cross-probe from a schematic to a waveform. This traffic is local to your device and is not transmitted to Ferrite.',
  ),
  CruxEulaBlock(
    isHeading: true,
    text: '7. Optional Features That Transmit Data',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'The following features are inactive until an Authorized User starts them. Each is described in the Privacy Policy, which governs the data handling.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '7.1 Update Checks. Where an Application offers an update check, it periodically requests an update manifest to determine whether a newer build is available. The request transmits the application version and operating system name. Enterprise deployments may disable update checks.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '7.2 Collaborative sessions. Where an Application offers a collaborative viewing or presenter session, the session is inactive until an Authorized User hosts or joins one. What is shared with other participants includes the host or joining user\'s display name, cursor position, the composition of the view being shared, and any annotations written during the session; waveform sample data itself is never shared, as each participant opens their own copy of the underlying file. On a local network, session data passes directly, peer to peer, between participants\' devices, and is not encrypted; access to a local session is controlled by the host, who approves each participant before anything is shared with them. Where participants are not on the same local network, session data is relayed through a message-relay server that forwards messages without storing session content, and session traffic is end-to-end encrypted with a key derived from the invitation, so the relay cannot read the content of a session. The relay does see connection metadata it cannot avoid handling in order to route the session, including room codes, IP addresses, connection times, and the size and timing of messages. There is no per-participant identity and no revocation: anyone holding the session invitation has access for the life of the session. Licensee is responsible for ensuring its Authorized Users host and join sessions only with people they trust, and that any session involving design data subject to a confidentiality obligation complies with that obligation.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '7.3 Bring-your-own-key AI features. Where an Application offers an AI feature, it is disabled until an Authorized User enables it and supplies an API key for a model provider of their choosing, or points it at a locally hosted model. Prompts and the design-derived context they carry travel from your device directly to the provider you selected. Ferrite operates no model, receives none of that content, and is not a party to your agreement with the provider. You are responsible for ensuring that submitting design data to your chosen provider complies with your own confidentiality and export-control obligations.',
  ),
  CruxEulaBlock(isHeading: true, text: '8. Telemetry'),
  CruxEulaBlock(
    isHeading: false,
    text:
        '8.1 What it is. The Applications collect anonymous usage measurements: which features are used and how often, plus the application version, operating system, form factor, display language, license tier, and a country code derived at the network edge. Each installation is identified only by a random identifier generated on that installation, which is not derived from your hardware and is not linked to you.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '8.2 What it never includes. Telemetry never includes file names, file paths, design data, signal or scope names, netlists, lint or simulation results, IP addresses, hardware identifiers, or any personal information. The Privacy Policy states the complete list.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '8.3 Your control. Each Application presents a disclosure on first launch with the choice in that same dialog, and a permanent switch in Settings → Privacy. In the European Economic Area, the United Kingdom, Switzerland, and South Korea, Telemetry is off unless you turn it on. Elsewhere it is on by default and you may turn it off at any time.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '8.4 Enterprise control. For the Enterprise Edition, Licensee\'s administrator may enable or disable Telemetry for the entire organization, and individual Authorized Users are not prompted.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '8.5 Deletion. Because Telemetry is not linked to your identity, the installation identifier is the only means of locating your data. The Application displays it in Settings → Privacy. Send it to privacy@ferriteengineering.com and Ferrite will delete the records carrying it.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '8.6 Verifiability. Ferrite publishes the source of the telemetry client as part of the open-source portion of each Application, so its behavior can be inspected rather than taken on trust.',
  ),
  CruxEulaBlock(isHeading: true, text: '9. Encryption and Export Control'),
  CruxEulaBlock(
    isHeading: false,
    text:
        '9.1 Cryptography in the Applications. The Applications use cryptography in two distinct ways, which have different legal characters:',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '(a) Digital signature verification. Every Edition verifies License Keys using an Ed25519 signature verification routine. It verifies signatures and cannot create them; it performs no encryption, no decryption, and no key exchange. The private signing key is held by Ferrite\'s licensing provider and is not present in any Application.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '(b) Encryption of collaborative sessions. Where an Application offers a collaborative session over a network that is not a local network, the session content is encrypted end-to-end using AES-256-GCM with keys derived from the session invitation. This is an implementation of a symmetric cipher, compiled into the Editions that offer the feature.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '9.2 Export classification. Ferrite\'s position is that the Applications are mass-market software under the Cryptography Note and are self-classified accordingly, and that they are exported under the applicable license exception. Ferrite files the reports and notifications its classification requires.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '9.3 Your obligations. Section 12 of the Terms applies without modification. You represent that you are not located in, and are not a national or resident of, a country or region subject to comprehensive sanctions; that you are not on a restricted-party list; and that you will not export, re-export, or transfer any Application to a prohibited destination, entity, person, or end use. Encryption software is subject to controls in some jurisdictions in addition to those of the United States, and you are responsible for compliance where you use the Applications.',
  ),
  CruxEulaBlock(isHeading: true, text: '10. Fees, Term, Renewal, and Lapse'),
  CruxEulaBlock(
    isHeading: false,
    text:
        '10.1 Open Core and Educational. No fee. An Educational License has a one-year term and is renewed by re-verifying eligibility under Section 4.2(c).',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '10.2 Pro. Billed per seat, monthly or annually, at the price in effect at purchase or renewal, and renews automatically for successive terms of the same length unless cancelled before the renewal date through Ferrite\'s then-current cancellation process.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '10.3 Enterprise. Fees, term, seat count, and renewal are as set out in the Order Form. Absent a different term there, an Enterprise License renews for successive periods matching the initial term unless either party gives written notice of non-renewal at least 30 days before the then-current term ends.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '10.4 Effect of lapse. If an Educational, Pro, or Enterprise License expires, is not renewed, or is terminated, the affected installation reverts to the Open Core Edition at the end of the applicable grace period under Section 5.4. Your data is unaffected. Design files, waveforms, sessions, workspaces, projects, and settings already on your device remain on your device and remain openable to the extent the Open Core Edition supports them. Only Educational-, Pro-, or Enterprise-tier features are gated.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '10.5 General. Section 15 of the Terms applies. Fees are exclusive of tax except where a payment processor acting as merchant of record collects tax as part of the transaction, and are non-refundable except as required by law or as expressly stated in an Order Form or in Ferrite\'s published refund policy.',
  ),
  CruxEulaBlock(isHeading: true, text: '11. Support'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Ferrite provides support for Educational, Pro, and Enterprise Licensees as described at the time of purchase; Enterprise Licensees receive priority support as described on the Pricing page. Support for the Open Core Edition is provided through public channels on a best-effort basis. Support does not include on-site services, custom development, or professional engineering advice, and Section 11 of the Terms (No Professional Advice) applies to any guidance Ferrite personnel provide.',
  ),
  CruxEulaBlock(isHeading: true, text: '12. Restrictions'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Section 6 of the Terms (License Restrictions) applies in full to all Editions, subject to Section 3 of this EULA. In addition, you will not:',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        '(a) use the Educational Edition for any commercial purpose (Section 4.2(b)); (b) exceed the seat count purchased under the applicable Order Form; (c) use a single Seat concurrently for more than one Authorized User except under a concurrent-use Order Form; (d) use an Enterprise License Key outside the organization identified on the Order Form; (e) share, publish, or resell a License Key; or (f) circumvent license verification, activation, or seat counting (Section 5.7).',
  ),
  CruxEulaBlock(isHeading: true, text: '13. Data Handling and Privacy'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Ferrite\'s collection and use of information is described in the Privacy Policy, incorporated into this EULA by reference. Your source files, netlists, waveform captures, simulation results, and project contents remain on your devices and are not collected by Ferrite, except through a feature the Privacy Policy describes as user-initiated. If Licensee requires a data processing agreement to reflect the EU or UK GDPR or a comparable law, contact legal@ferriteengineering.com. Because the Applications do not transmit Licensee\'s design data to Ferrite in ordinary operation, Ferrite does not act as Licensee\'s processor with respect to that data. For collaborative-session relay traffic, Ferrite cannot read session content and does not act as a processor with respect to that content, but Ferrite does handle connection metadata (such as IP addresses and connection timing) needed to route a session, and acts as a processor with respect to that metadata where it constitutes personal data. The same is true of any other user-initiated feature Licensee chooses to enable that transmits data to Ferrite.',
  ),
  CruxEulaBlock(isHeading: true, text: '14. Confidentiality'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Each party may disclose non-public business or technical information to the other in connection with an Enterprise evaluation, procurement, or support relationship ("Confidential Information"). The receiving party will use Confidential Information only to exercise its rights and perform its obligations under this EULA, will protect it using at least the same degree of care it uses for its own confidential information of similar importance, and will not disclose it to a third party without the disclosing party\'s prior written consent, except to a professional advisor bound by confidentiality or as required by law after notice to the disclosing party where notice is not itself prohibited. This Section does not apply to information that is or becomes public without breach, was already known to the receiving party without an obligation of confidentiality, or is independently developed without use of the Confidential Information. This Section survives for three years after disclosure, and indefinitely for trade secrets.',
  ),
  CruxEulaBlock(
    isHeading: true,
    text: '15. Warranty Disclaimer; Limitation of Liability',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Section 18 (Disclaimer of Warranties) and Section 19 (Limitation of Liability) of the Terms apply to all Editions. For an Enterprise Licensee that has paid fees under an Order Form, the reference in Terms Section 19.2 to amounts paid in the preceding twelve months means the fees actually paid under that Order Form during that period. For the Open Core and Educational Editions, which are provided at no charge, Ferrite\'s aggregate liability is limited to the greater of the amount you paid (if any) and one hundred United States dollars (US\$100).',
  ),
  CruxEulaBlock(isHeading: true, text: '16. Term, Suspension, and Termination'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Section 16 of the Terms applies. In addition, Ferrite may suspend an Enterprise License, after notice and a reasonable opportunity to cure, if Licensee materially exceeds its purchased seat count and does not true up within 30 days of that notice; and Ferrite may revoke an Educational License that is used in breach of Section 4.2(b) or whose eligibility can no longer be established. Termination of a paid Edition does not terminate your rights in the Open Core Edition or in any Open-Source Component.',
  ),
  CruxEulaBlock(isHeading: true, text: '17. Governing Law; Dispute Resolution'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Section 21 of the Terms applies without modification, except that an Enterprise Order Form may specify a different venue or dispute-resolution mechanism for disputes arising solely under that Order Form, in which case the Order Form controls solely as to that subject matter.',
  ),
  CruxEulaBlock(isHeading: true, text: '18. U.S. Government End Users'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'The Applications are "commercial computer software" and "commercial computer software documentation" as those terms are used in FAR 12.212 and DFARS 227.7202. Government end users acquire only those rights set out in this EULA and the Terms.',
  ),
  CruxEulaBlock(isHeading: true, text: '19. General'),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Section 24 of the Terms (General Provisions) applies. This EULA, the Terms, the Privacy Policy, and any Order Form together constitute the entire agreement between the parties regarding the Applications and supersede all prior discussions on that subject matter.',
  ),
  CruxEulaBlock(
    isHeading: false,
    text:
        'Ferrite Engineering LLC · 1500 N Grant St Ste N, Denver, CO 80203 · legal@ferriteengineering.com',
  ),
];
