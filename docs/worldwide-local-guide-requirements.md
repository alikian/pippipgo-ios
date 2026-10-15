# Codex: Upgrade PipPipGo Into an Intelligent, Worldwide Local Tour Guide

## 1. Product Vision — The Most Important Requirement

PipPipGo is not a traditional audio tour, a navigation app, or a directory of nearby attractions.

**Pip is an intelligent local guide who knows what's interesting, what is coming up, when to mention it, and why someone might enjoy it.**

Google Maps and Places provide geographic information. Pip turns that information into meaningful, enjoyable, personalized travel experiences.

Our competitive advantage is NOT simply identifying places. It is understanding:

- **WHAT** is worth mentioning.
- **WHY** it would interest this particular traveler.
- **WHEN** it is the right moment to mention it.
- **WHERE** it is relative to the traveler and their direction of travel.
- **HOW** to introduce it naturally and make it feel exciting.
- **WHETHER** the traveler should consider a spontaneous detour.

Imagine driving with an enthusiastic, knowledgeable local friend who knows the area's hidden gems, famous attractions, interesting stories, favorite hangouts, and beautiful scenery.

That is the experience we want.

**This intelligence must work worldwide, not just in San Diego.**

---

## 2. The Problem We Discovered During Testing

We tested Pip's Live Driving Tour between Carmel Valley and Carlsbad, California.

Pip correctly recognized Torrey Pines High School and provided an interesting historical introduction.

However, during the rest of our drive, it missed many destinations and experiences:

- Del Mar Highlands Town Center — dining, shopping, entertainment.
- One Paseo — popular outdoor restaurants, shops, and social hangouts.
- Del Mar Beach — potentially beautiful sunset viewing.
- Downtown Del Mar — boutiques, restaurants, and walkable streets.
- Scenic viewpoints, coastal bridges, public art, and photo opportunities.
- Del Mar Fairgrounds — popular event destination.
- Solana Beach — a distinctive coastal community.
- Cedros Avenue Design District — art, design, galleries, shopping.
- Carlsbad Premium Outlets.
- LEGOLAND California.
- Costco, In-N-Out, and other useful or popular stops.
- Beautiful ocean views along coastal driving routes.

Pip did recognize the Carlsbad Flower Fields.

The problem is that Pip appears primarily reactive, announcing individual nearby landmarks rather than understanding the broader travel experience.

**We need to transform Pip from a landmark detector into a predictive local guide.**

---

## 3. Worldwide Google Maps and Places Integration

Use Google Maps Platform as our primary global geographic and POI discovery source.

Investigate and improve existing integrations with:

- Google Places API (New): Nearby Search
- Google Places API (New): Text Search
- Google Place Details and Photos
- Google Routes API and supported search-along-route features
- Google Geocoding and available geographic boundary data

### Global requirements

Pip should work in Tokyo, Paris, Istanbul, Tehran, Dubai, Rome, Toronto, San Diego, and smaller towns worldwide wherever adequate geographic data exists.

Do not hardcode specific cities, regions, or attractions.

Use the same global discovery engine everywhere.

Retrieve local attractions, restaurants, businesses, shopping areas, scenery, cultural landmarks, and points of interest dynamically.

Use localized place names, the traveler's selected language, and culturally appropriate context.

Google Places coverage isn't exhaustive. Supplement it with appropriately licensed geographic sources where necessary, particularly for natural scenery, ocean viewpoints, bridges, public art, and other features that Google Places may not represent well.

Respect provider data licensing, attribution, storage restrictions, and rate limits.

Offline mode must remain supported through compliant offline data sources, without depending on unavailable online Google Places requests.

---

## 4. Predictive, Route-Aware Discovery

Pip must search AHEAD of the traveler, not simply within a fixed circle around their current GPS position.

Use:

- GPS coordinates.
- Direction and heading.
- Vehicle speed.
- Road geometry and map matching.
- Available navigation route.
- Estimated forward travel corridor when no route is active.
- Road access and realistic detours.
- Estimated travel time.
- Current location and local geographic context.

### Initial configurable discovery ranges

| Mode | Suggested discovery range |
|---|---|
| Walking | 0.3–1 mile |
| Urban driving | 1–3 miles |
| Major roads | 3–5 miles ahead |
| Highway driving | 5–10 miles ahead |
| Major destinations | Up to 15 miles when relevant |

Adapt dynamically to speed, road type, POI density, and significance.

These are initial settings to tune through testing.

At highway speeds, Pip should identify attractions early enough that the traveler has time to consider an exit.

Do not suggest unsafe or unrealistic turns.

When an attraction requires a detour, distinguish that from continuing along the current road.

---

## 5. Expand Discovery Beyond Historical Attractions

Pip must actively explore a broad range of categories.

### Categories

**Scenery and nature**
Beaches, sunsets, ocean views, coastal overlooks, mountains, gardens, scenic roads, waterfalls.

**Entertainment**
Concert venues, theaters, amusement parks, nightlife, festivals, comedy clubs.

**Food and drinks**
Local favorites, popular restaurants, cafés, food districts, famous chains, special dining experiences.

**Shopping**
Outdoor malls, shopping streets, luxury districts, outlets, markets, Costco, major retail destinations.

**Arts and culture**
Art galleries, design districts, museums, architecture, sculptures, street art, and cultural neighborhoods.

**Local lifestyle**
Popular hangouts, main streets, charming downtowns, social gathering places, and neighborhood favorites.

**Family activities**
LEGOLAND, zoos, aquariums, parks, family entertainment centers.

**Photography**
Interesting bridges, sculptures, viewpoints, colorful streets, notable buildings, and scenic overlooks.

**History**
Landmarks, historic buildings, local stories, and culturally significant places.

**Practical road-trip stops**
Restrooms, gas, EV charging, grocery stores, rest areas, and convenient food stops.

**Seasonal experiences**
Flower fields, holiday decorations, fairs, farmers markets, seasonal festivals.

Do not prioritize a historical landmark merely because it has historical information.

A vibrant restaurant district may be much more interesting to a traveler than a nearby historical building.

Also, do not treat all businesses as equally worth narrating. A Costco or In-N-Out may be useful to surface, but shouldn't automatically receive narration over an exceptional scenic attraction.

---

## 6. Build Pip's Core Intelligence Engine

### This is the heart of our product.

Create or improve a reusable **Experience Intelligence Engine** that evaluates discovered places and selects the best opportunities to narrate.

Each POI should receive a contextual relevance score based on:

1. **Intrinsic visitor appeal:** Is this place genuinely interesting, famous, distinctive, scenic, or locally popular?

2. **Personal relevance:** Does it match the user's interests, companions, previous experiences, and travel preferences?

3. **Timing:** Is there something special about visiting now? Sunset, weather, season, opening hours, or events?

4. **Proximity and accessibility:** How soon will the traveler reach it? Is it accessible from the current road?

5. **Experience value:** Is it worth exploring, photographing, eating at, shopping at, or simply hearing about?

6. **Uniqueness:** Is it something special about this particular city or region?

7. **Narration freshness:** Have we already mentioned it? Would another destination add more variety?

8. **Opportunity urgency:** Must it be mentioned now because the traveler will soon pass an exit or miss a temporary experience?

9. **Information confidence:** Do reliable sources support the recommendation, description, timing, and directions?

Use configurable ranking weights and context-specific rules rather than relying solely on distance or Google ratings.

### The critical question

Before Pip speaks, the system should be able to answer:

**"Why is this particular place worth telling this particular traveler about at this particular moment?"**

If the system cannot answer that convincingly, Pip should usually remain silent.

Don't turn Pip into a nonstop business advertisement or automated directory.

Keep some room for delightful discoveries outside the traveler's known preferences.

---

## 7. Proactive Narration — Make People Curious

Pip should announce important experiences BEFORE travelers reach them.

### Example: Del Mar

"You're getting close to Del Mar, one of San Diego's prettiest coastal towns. There's a charming downtown with wonderful restaurants and shops. And with sunset coming up, the beach could be a beautiful little detour."

### Example: One Paseo

"Just nearby is One Paseo, a favorite local spot for outdoor dining and shopping. It's a great place to hang out for a while."

### Example: Solana Beach

"Welcome to Solana Beach! If you love art or design, there's a fantastic little district on Cedros Avenue with galleries, boutiques, and some really interesting shops."

### Example: Carlsbad

"You're approaching Carlsbad! There's quite a bit to explore here, from LEGOLAND and the outlet mall to beaches and great restaurants."

### Example: Scenic drive

"Take a look to your right when it's safe — there's a beautiful ocean view along this stretch of the road."

These are examples of the desired voice and personality, not scripts to hardcode.

Narration should be friendly, warm, knowledgeable, concise, and sometimes delightfully surprising.

Usually keep initial narration around **10–15 seconds**, with the option for the user to ask for more.

Display the relevant destination image when available.

Never invent business hours, visibility, travel times, local events, or scenic conditions.

---

## 8. Understand Cities, Neighborhoods, and Travel Transitions

Pip should recognize when users enter:

- A new city.
- A new neighborhood.
- A famous district.
- A coastal town.
- A downtown area.
- A culturally significant region.

Introduce the character of the area and two or three highlights.

Example:

"Welcome to Carlsbad! It's a beautiful coastal city known for its beaches, relaxed atmosphere, and family attractions."

Avoid repeating city introductions or responding to minor GPS boundary fluctuations.

Use reliable geography rather than guessing city boundaries from the closest business.

---

## 9. Scenic Awareness and Left/Right Intelligence

Pip should identify noteworthy views and attractions along roads.

Examples include:

- Ocean views.
- Mountain landscapes.
- Interesting bridges.
- Public sculptures.
- Scenic overlooks.
- Dramatic architecture.
- Photography opportunities.

Calculate whether the destination is to the left, right, ahead, or behind the traveler using heading and geographic geometry.

Only claim that something is visible when the available data supports it.

Be careful not to encourage drivers to look away from the road. Use safe, brief audio descriptions.

For example:

"There's a beautiful coastal viewpoint coming up on your right."

Or:

"Just off the next exit is a popular photo spot."

---

## 10. Real-Time Opportunity Detection

Pip should understand when timing makes an experience particularly appealing.

Consider:

- Sunrise and sunset times.
- Local weather.
- Season and daylight.
- Day of the week.
- Verified opening hours.
- Available event information.
- Traveler preferences.
- Realistic travel times.

Example:

"It's almost sunset, and there's a beautiful beach just a few minutes away. Would you like to hear about it?"

Recognize seasonal destinations and avoid recommending them as currently active if they are closed.

Do not make unsupported claims about weather, crowds, visibility, or events.

---

## 11. Smart Conversation and Narration Scheduler

Pip should be proactive without being annoying.

Create an intelligent scheduler that controls which discoveries deserve immediate narration.

### Guidelines

- Look for important experiences several minutes ahead.
- Announce opportunities early enough to act on them.
- Keep narration generally between 8 and 15 seconds.
- Avoid repeating the same information.
- Combine related destinations into a short neighborhood introduction.
- Adapt speech frequency to driving speed, attraction density, and user engagement.
- Allow exceptional, time-sensitive opportunities to override normal cooldowns.
- Avoid interrupting the user.

When the user asks a question, that conversation takes priority.

When live translation is active, respect its audio priorities and avoid interfering with translation.

Make narration frequency configurable, with future options for Quiet, Balanced, and Discover More experiences.

Pip should feel conversational and intelligent, not like it is reading a predetermined list.

---

## 12. Respect Personalization Without Creating Blind Spots

Use the user's existing travel profile.

For example:

- Art lover → galleries and design districts.
- Family with children → entertainment and family activities.
- Food lover → interesting restaurants and culinary neighborhoods.
- Photographer → scenic views and photo opportunities.
- Shopping enthusiast → famous shopping areas and boutiques.
- Road-trip traveler → useful stops and memorable detours.

However, don't completely exclude other categories.

Someone who enjoys art may still appreciate a spectacular sunset or a famous local food stop.

Pip should balance personalization with curiosity and discovery.

---

## 13. Preserve Existing PPG Functionality

This is an intelligence and discovery upgrade, NOT a full application redesign.

Do not remove, replace, or break:

- The existing minimalist interface.
- Pip's current voice and personality.
- Walking Tour mode.
- Driving Tour mode.
- Online/offline modes.
- Headphone and Bluetooth audio.
- Live translation.
- Existing conversation handling.
- Destination images.
- Map features.
- Social sharing and Pip pins.
- User travel profile.
- Current navigation and location functionality.

Preserve Pip's existing branding and visual design.

Focus changes on the discovery, ranking, prediction, narration, and contextual awareness systems.

---

## 14. Performance, Cost, and Reliability

Build the discovery process efficiently.

Requirements:

- Pre-fetch upcoming POIs as appropriate.
- Use intelligent search refresh intervals.
- Deduplicate overlapping API requests.
- Avoid fetching unnecessary Place Details fields.
- Use appropriate API field masks.
- Separate frequently changing information from relatively static geography.
- Reuse data only where provider policies permit.
- Handle weak connectivity and API failures gracefully.
- Avoid repeated narration as GPS updates.
- Keep narration responsive while discovery happens.
- Make usage, latency, and cost measurable.

Use a provider abstraction where practical so other geographic data sources can supplement Google without rewriting the intelligence engine.

No unsupported scraping or prohibited caching of Google Maps content.

---

## 15. Test With Our Actual Driving Route

Build a simulated GPS replay covering:

Carmel Valley → Del Mar Highlands → One Paseo → Del Mar area → I-5 North → Del Mar Fairgrounds → Solana Beach vicinity → Carlsbad.

Use realistic road geometry and travel direction.

Test at different driving speeds, times of day, and user profiles.

### Expected behavior

Pip should identify and appropriately prioritize:

- One Paseo and Del Mar Highlands.
- Del Mar Beach and downtown Del Mar.
- Sunset opportunities when relevant.
- Major scenic coastal features.
- Del Mar Fairgrounds.
- Solana Beach and Cedros Design District.
- Carlsbad Premium Outlets.
- LEGOLAND.
- Carlsbad Flower Fields when seasonally relevant.
- Useful shopping and food stops when contextually appropriate.

Not every place must be spoken aloud. The important test is that relevant candidates are discovered, ranked correctly, and narrated at useful moments.

### International test routes

Also simulate routes in:

- Tokyo.
- Paris.
- Istanbul.
- Toronto.
- A smaller town with fewer attractions.

The same engine should adapt without city-specific code.

Test both with and without active navigation.

---

## 16. Diagnostic Logging and Evaluation

Add debugging tools that explain Pip's decisions.

For each discovery cycle, log:

- GPS position and travel heading.
- Road type and speed.
- Search radius or route corridor.
- Search categories used.
- POIs returned.
- Candidate scores and ranking factors.
- Reasons places were selected or rejected.
- Narration timing and cooldown decisions.
- Missing data or API errors.
- Cost and latency metrics.

We need to know WHY Pip missed a place.

Was it outside the search radius?

Was the Google query too narrow?

Was the attraction excluded by its category?

Was the ranking score too low?

Was narration suppressed by a cooldown?

Without this visibility, we cannot meaningfully improve the experience.

Add regression tests and measurable evaluation scenarios for discovery quality, timeliness, relevance, diversity, repetition, and narration accuracy.

---

## 17. Implementation Instructions for Codex

1. First inspect the existing codebase and map the complete GPS → discovery → POI ranking → narration pipeline.

2. Identify the root causes behind the missed POIs in our driving test.

3. Reuse the existing architecture and integrations when suitable. Avoid unnecessary rewrites.

4. Implement a modular, worldwide discovery and Experience Intelligence Engine.

5. Improve route prediction, ranking, and proactive narration scheduling.

6. Keep major thresholds and weights configurable.

7. Add automated tests and simulated GPS replay tests.

8. Preserve existing functionality and verify nothing regresses.

9. Report what changed, how it was tested, and any remaining limitations or costs.

Do not stop at a design proposal. Implement the improvements in the existing project, run available tests, and clearly identify anything that cannot be completed with the current APIs, configuration, or infrastructure.

---

# Final Success Criteria

We succeed when someone can activate Pip anywhere in the supported world and feel like they immediately have a knowledgeable local guide.

Pip should not merely say:

"On your right is a shopping center."

Pip should know whether that shopping center is worth mentioning, whether it matches the traveler's interests, and whether this is a useful moment to introduce it.

**Google knows where places are. Pip understands why they matter.**

Our goal is to create the delightful feeling of discovering something wonderful that you otherwise would have driven right past.

That is the product we are building.