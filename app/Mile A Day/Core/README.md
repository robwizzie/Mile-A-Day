# MAD App - Theme & Onboarding System

This document provides an overview of the newly implemented MAD (Mile A Day) app theme system, splash screen, onboarding flow, and authentication UI.

## 🎨 Theme System (`Core/Theme/MADTheme.swift`)

A comprehensive design system based on the MAD logo's red, black, and white color scheme:

### Colors

-   **MAD Red**: Primary brand color (`#D84056`)
-   **MAD Black**: Rich black for text and UI elements
-   **MAD White**: Clean white backgrounds
-   **Gradients**: Beautiful red and black gradients for visual interest

### Typography

-   Rounded system font family for modern feel
-   Consistent sizing from captions to large titles
-   Proper hierarchy and weights

### Components

-   `MADPrimaryButtonStyle`: Red gradient buttons
-   `MADSecondaryButtonStyle`: Outlined buttons
-   `MADTertiaryButtonStyle`: Text-only buttons
-   `MADCardStyle`: Consistent card styling with shadows

### Usage

```swift
Button("Get Started") {
    // action
}
.madPrimaryButton(fullWidth: true)

VStack {
    // content
}
.madCard()
```

## 🚀 App Flow (`Core/State/AppStateManager.swift`)

Manages the complete app lifecycle:

1. **Splash Screen** (2.5 seconds with animations)
2. **Onboarding** (for first-time users)
3. **Authentication** (Apple/Google sign-in UI)
4. **Main App** (existing TabView)

### States

-   `.splash` - Animated logo and branding
-   `.onboarding` - 4-screen walkthrough
-   `.authentication` - Sign-in options
-   `.main` - Full app experience

## 📱 Views

### Splash Screen (`Views/Splash/SplashView.swift`)

-   Animated MAD logo recreation
-   Smooth transitions and speed lines
-   Brand messaging and colors

### Onboarding (`Views/Onboarding/OnboardingView.swift`)

-   4 informative screens:
    1. Track Your Daily Mile
    2. Earn Badges & Rewards
    3. Connect with Friends
    4. Monitor Your Progress
-   Smooth page transitions
-   Interactive navigation

### Authentication (`Views/Auth/AuthenticationView.swift`)

-   Apple Sign In button (black)
-   Google Sign In button (white with border)
-   Guest access option
-   Terms and privacy links
-   **Note**: UI-only implementation for visual design

### Profile (`Views/Profile/ProfileView.swift`)

-   Redesigned with MAD theme
-   User stats in beautiful cards
-   Settings navigation
-   Development controls (logout/reset for testing)

## 🎯 Key Features

### Animations

-   Smooth state transitions with `MADTheme.Animation`
-   Logo scaling and fading effects
-   Speed line animations
-   Bounce and spring animations

### Responsive Design

-   Consistent spacing system
-   Flexible layouts
-   Proper typography scaling
-   Shadow and corner radius consistency

### Development Features

-   Reset functionality for testing flows
-   Debug-only development controls
-   Preview support for all components

## 🔧 Integration

The system integrates seamlessly with existing:

-   HealthKit manager
-   User management
-   Notification services
-   Background services

### Root View Coordinator (`Views/Root/RootView.swift`)

Orchestrates the entire app flow and applies theme globally to navigation and tab bars.

## 🎨 Visual Consistency

All UI elements now follow the MAD brand:

-   Consistent red accent color
-   Rounded design language
-   Clean white backgrounds
-   Subtle shadows and depth
-   Professional typography

The design creates a cohesive, modern fitness app experience that motivates users to stay active daily.
