-- D5 partie 2 : traduction anglaise des documents légaux en vigueur (version du 31/10/2026).
-- Information seulement : la version française fait foi (rappelé en tête de chaque traduction).
-- TRADUCTION À FAIRE RELIRE AVEC LES TEXTES FRANÇAIS AVANT L'OUVERTURE COMMERCIALE.

insert into public.legal_translations (document_id, language, title, body)
select d.id, 'en', t.title, t.body
from (values
('terms', 'General terms of use', $terms$
_This English translation is provided for information. The French version is the reference version and is the one you accept._

## 1. Purpose and publisher
These terms govern the use of the Coupon Pro IA application (the “Service”), published by {{editeur}} {{forme}}, {{adresse}}, {{pays}}, {{immatriculation}}. Contact: {{contact}}.
Creating an account and using the Service require having read and accepted these terms and the privacy policy.

## 2. What the Service offers
Coupon Pro IA is a platform for football analysis and the creation of prediction content:
- match analyses, probabilities estimated by a statistical model and comments written with the help of an artificial intelligence from verified data;
- coupons proposed by the platform, coupon-building assistant, laboratory, graphic studio;
- community space and Tipster profiles;
- tracking of results and statistics calculated by the platform.
**Coupon Pro IA is not a bookmaker.** No bet is taken, placed or collected in the application, and no coupon created in the application corresponds to a bet actually placed.

## 3. Nature of the content
- Predictions and probabilities are **estimates**, never certainties. Sports results are uncertain.
- Past performance does not predict future performance. **No profit is promised.**
- The odds shown come from third-party sources at a given moment and may change at any time.
- Sports data (fixtures, line-ups, absences, scores) come from third-party providers and may be incomplete or late; they are shown as received.
- Any betting decision made elsewhere is the sole responsibility of the user. The publisher cannot be held liable for a loss related to a bet placed with a third-party operator.

## 4. Access and account
- The Service is **reserved for adults** (18 years old, or the age of majority in their country if higher).
- The user provides a valid e-mail address, keeps their password confidential and remains responsible for the use of their account.
- An account is personal. Accounts created to get around a limit, a suspension or a quota may be deleted.

## 5. Plans, credits and payments
- The plans (FREE, STARTER, PRO TIPSTER, BUSINESS) and their prices in FCFA are shown in the “Subscription and credits” screen. Prices may change; the price paid is the one shown and confirmed at the time of payment.
- Payment is made by Mobile Money through the CinetPay aggregator. A plan or credits are activated only after the operator confirms the payment, checked by the server.
- A plan covers the period purchased (1 month or 12 months). **There is no automatic renewal**: the user extends it if they wish.
- AI credits included in a plan are renewed every month and do not carry over; credits bought in packs do not expire.
- A promo code can be used once per account, within its validity conditions.
- Any refund request goes to support ({{contact}}). It is reviewed case by case, in particular for a double payment or when the paid service cannot be accessed. A refund that is granted removes the corresponding rights (plan stopped, remaining credits removed).

## 6. Content published by users
- The user remains responsible for what they publish (profile, posts, comments, coupons, visuals) and follows the Community rules.
- They grant the publisher the non-exclusive right to display this content in the Service while it is published.
- A coupon published by a Tipster can no longer be changed or deleted: its results, won or lost, are settled and shown by the platform. Only deleting the account removes it.
- The publisher may hide content or suspend an account that breaks these terms or the Community rules. Anyone can report content.

## 7. Graphic studio
The visuals generated carry the planned warnings. A user who shares them agrees not to present them as assured profits and not to remove the warning notices.

## 8. Responsible gaming
Sports betting carries a risk of losing money and of addiction. The “Responsible gaming” page of the application recalls good practices and warning signs. If you have difficulties, talk to someone close to you or to a health professional.

## 9. Availability and liability
The Service is provided as is, with an obligation of means. It may be interrupted for maintenance, if a provider fails or in case of force majeure. The publisher is not responsible for users' content and decisions or for data supplied by third parties.

## 10. Intellectual property
The application, its brand, logo, texts, analyses and graphic templates belong to the publisher or its partners. Any unauthorised reproduction is forbidden, except for sharing the visuals created by the user in the studio.

## 11. Account deletion
The user can delete their account at any time from Profile → “Delete my account”. Deletion is final. Sums already paid for a current period are not refunded merely because of the deletion.

## 12. Personal data
Data processing is described in the Privacy policy.

## 13. Changes to the terms
The terms may be updated. Each new version is dated and must be accepted in the application to keep using the Service.

## 14. Applicable law and disputes
These terms are governed by the law of the country where the publisher is established ({{pays}}), without depriving the user of the mandatory protections of their country of residence. Before any action, the parties seek an amicable solution in writing with support.
$terms$),
('privacy', 'Privacy policy', $privacy$
_This English translation is provided for information. The French version is the reference version and is the one you accept._

## 1. Data controller
{{editeur}} {{forme}}, {{adresse}}, {{pays}}. Contact for any question about your data: {{contact}}.

## 2. Data processed and why
- **Account**: e-mail address, password (stored in encrypted form, never readable), display name. To create and secure your account.
- **Preferences**: competitions and teams followed, level, text size, notification settings and quiet hours. To personalise the application.
- **Use of the service**: saved coupons, requests to the assistant and the laboratory, use of credits and analyses. To provide the service and apply your plan's quotas.
- **Community** (if you use it): Tipster profile, photo, posts, comments, reactions, follows, reports, blocks. To run the community space and moderation.
- **Studio**: logo, cover, signature and generated visuals. To produce your visuals.
- **Payments**: plan or pack bought, amount, transaction reference, status, payment method given by the operator. Your Mobile Money credentials are entered with the operator and are not received by the application.
- **Notifications**: technical identifier of the device to send notifications, if you accept them.
- **Security**: log of sensitive actions (administration, payments, moderation) and technical server logs.
Sports data (matches, odds, results) are not personal data.

## 3. Legal bases
Performance of the service you request (account, plan, features used), your consent (notifications on the phone, posts in the community), compliance with legal obligations and the legitimate interest of securing the service and preventing abuse.

## 4. Artificial intelligence
The texts you send to the assistant or the laboratory, together with the necessary match and coupon data, are sent to the Gemini artificial intelligence service (Google) to write the answers. Do not include unnecessary personal information. Selections, odds, probabilities and results are always calculated by our servers, not by the AI.

## 5. Recipients and providers
Your data is neither sold nor rented. It is accessible to the authorised team (support, administration, moderation) and processed by the following technical providers on our behalf:
- **Supabase**: hosting of the database, files and authentication, on servers located in the European Union (Ireland);
- **Google**: Gemini (artificial intelligence) and Firebase Cloud Messaging (notifications);
- **CinetPay**: processing of Mobile Money payments;
- **API-Football**: provider of sports data (no personal data is sent to it).
These providers may process data outside your country of residence. The Tipster profile, posts and published coupons are visible to other users; people you block no longer see them.

## 6. Retention periods
Your data is kept as long as your account exists. When you delete your account (Profile → “Delete my account”), your account data, preferences, coupons, posts, comments, files and payment history are erased. The security log keeps a record of the deletion, without personal content. Technical server logs are kept for a limited period by our providers.

## 7. Security
Encrypted exchanges (HTTPS), data access controlled row by row according to the user and their rights, encrypted passwords, third-party service keys only on the servers, sensitive actions logged. As no measure offers absolute security, report any problem to us at {{contact}}.

## 8. Your rights
You can access your data, correct it (Profile), delete it (account deletion), object to some processing (notification settings) and request a copy of your data by writing to {{contact}}. You can also contact the data protection authority of your country, for example the CIL in Burkina Faso, ARTCI in Côte d'Ivoire or the CDP in Senegal.

## 9. Minors
The Service is reserved for adults. If we learn that an account belongs to a minor, it is deleted.

## 10. Trackers
The application includes no third-party advertising or audience measurement tool. It keeps your login session and display settings on your phone.

## 11. Changes
This policy may be updated. Each new version is dated and must be accepted in the application.
$privacy$),
('community', 'Community rules', $community$
_This English translation is provided for information. The French version is the reference version._

## Spirit
The Coupon Pro IA community is for sharing analyses and coupons transparently. Tipster statistics are calculated by the platform, on coupons published before kick-off that cannot be changed afterwards.

## Forbidden
- Promising profits or presenting a prediction as certain (“sure”, “guaranteed”, “assured win”, “100%”…).
- Publishing fake results, edited screenshots or statistics that cannot be checked.
- Selling predictions, “fixed matches” or paid access, or redirecting to other payment services: these are common scams.
- Insulting, harassing, threatening, or making hateful or discriminatory remarks.
- Publishing other people's personal data (number, address, private photos).
- Publishing illegal, violent or sexual content, or content targeting minors.
- Spamming, creating several accounts or impersonating someone else.
- Encouraging excessive gambling, borrowing, or betting money needed for daily life.

## Report and block
Every post and every comment can be reported. You can block a user: you no longer see their content and they can no longer interact with you.

## Sanctions
Depending on severity: content hidden, Tipster profile suspended, account suspended or deleted. Moderation decisions are logged.
$community$)
) as t(code, title, body)
join public.legal_documents d on d.code = t.code and d.version = '2026-10-31'
on conflict (document_id, language) do nothing;
