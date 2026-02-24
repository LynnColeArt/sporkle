> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Contributing to Sparkle

Thank you for your interest in contributing to Sparkle! We believe in the power of community to democratize AI compute.

## 🤝 Code of Conduct

Be excellent to each other. We're building the people's AI infrastructure together.

## 🐛 Reporting Bugs

Bugs are not failures - they are our teachers! When reporting bugs:

1. Check if the issue already exists
2. Include system information (OS, compiler, GPU types)
3. Provide minimal reproducible example
4. Describe expected vs actual behavior

## 🚀 Suggesting Features

We love new ideas! When suggesting features:

1. Explain the use case
2. Describe how it helps democratize AI compute
3. Consider how it works across diverse hardware

## 💻 Development Process

### Our Philosophy
- **Purple Engineer's Hat** 🟣: Build fearlessly, try impossible things
- **QA Beanie with Propellers** 🧢: Ask hard questions, no ego attached

### Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Follow our coding style (Pythonic Fortran)
4. Test on diverse hardware if possible
5. Commit with clear messages
6. Push and create a Pull Request

### Coding Style

Please follow our [Style Guide](STYLE_GUIDE.md) and [Quick Reference](STYLE_QUICK_REFERENCE.md).

Key points:
- **Strong typing always** - explicit types with kinds
- **Pythonic Fortran** - explicit over implicit  
- Use `implicit none` everywhere
- Descriptive variable names (no abbreviations)
- Initialize all derived type components
- Comment the "why", not the "what"
- Prefer array operations over explicit loops

### Testing

- Test on multiple device types when possible
- Include edge cases (device failure, mixed hardware)
- Ensure backward compatibility

## 📚 Documentation

Help us improve documentation:
- Fix typos
- Add examples
- Clarify confusing sections
- Translate to other languages

## 🌟 Ways to Contribute

### Code Contributions
- Implement new device backends (FPGAs, TPUs, etc.)
- Optimize collective algorithms
- Add new operations
- Improve error handling

### Non-Code Contributions
- Test on unusual hardware configurations
- Write tutorials and blog posts
- Create visualizations of mesh topologies
- Help with community support

### Hardware Contributions
- Run compatibility tests on your devices
- Contribute compute time to the test mesh
- Report performance metrics

## 🔄 Pull Request Process

1. Update documentation for new features
2. Add tests for new functionality
3. Ensure all tests pass
4. Update CHANGELOG.md
5. Request review from maintainers

## 🎯 Priorities

Current focus areas:
- Multi-node mesh communication
- More GPU backend implementations
- Performance optimization
- Documentation and examples

## 💬 Communication

- GitHub Issues: Bug reports and features
- Discussions: General questions and ideas
- Pull Requests: Code contributions

## 🏆 Recognition

Contributors are recognized in:
- AUTHORS file
- Release notes
- Special badges for significant contributions 🍬

Remember: Every contribution matters, from fixing typos to implementing new backends. Together, we're building infrastructure that ensures AI serves everyone.

**"By the people, for the people."**